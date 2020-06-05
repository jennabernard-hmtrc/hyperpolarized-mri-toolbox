function [params_fit, Sfit, ufit, error_metrics] = fit_aKG_kinetics(S, TR, flips, params_fixed, params_est, noise_level, plot_flag)
% fit_pyr_kinetics - Kinetic model fitting function for HP 13C MRI.
%
% Fits product signals, assuming origination from a single substrate
% In other words, pyruvate to lactate, bicarbonate and alanine.
% An "input-less" method is used, eliminating
% need to make any assumptions about the input function.
% This uses the following assumptions:
%   - uni-directional conversion from substrate to metabolic products (i.e.
%   pyruvate to lactate)
% It also allows for fixing of parameters. Based on simulations, our
% current recommendation is to fix pyruvate T1, as it doesn't impact kPX substantially.
%
% [params_fit, Sfit, ufit, objective_val] = fit_pyr_kinetics(S, TR, flips, params_fixed, params_est, noise_level, plot_flag)
%
% All params_* values are structures, including possible fields of 'kPL', 'kPB', 'kPA', (1/s),
% 'R1P', 'R1L', 'R1B', 'R1A' (1/s).
% INPUTS
%	S - signal dynamics [voxels, # of metabolites, # of time points]
%		Substrate (e.g. Pyruvate) should be the first metabolite, followed by each product
%   TR - repetition time per time point
%	flips - all flip angles [# of metabolites, # of time points x # of phase encodes]
%	params_fixed - structure of fixed parameters and values (1/s).  parameters not in
%       this structure will be fit
%   params_est (optional) - structure of estimated values for fit parameters pyruvate to metabolites conversion rate initial guess (1/s)
%       Also can include upper and lower bounds on parameters as *_lb and
%       *_ub (e.g. R1L_lb, R1L_ub)
%   noise_level (optional) - estimate standard deviation of noise in data
%       to use maximum likelihood fit of magnitude data (with Rician noise
%       distribution)
%   plot_flag (optional) - plot fits
% OUTPUTS
%   params_fit - structure of fit parameters
%   Sfit - fit curves
%   ufit - derived input function (unitless)
%   error_metrics - measurements of fit error, including upper/lower
%   bounds, estimated kPL error, Rsquared, and Chisquared (untested)
%
% EXAMPLES - see test_fit_pyr_kinetics.m
%
% Authors: John Maidens,  Peder E. Z. Larson
%
% (c)2015-2018 The Regents of the University of California. All Rights
% Reserved.

isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;


size_S = size(S);  ndimsx = length(size_S)-2;
Nt = size_S(end); t = [0:Nt-1]*TR;
Nx = size_S(1:ndimsx);
if isempty(Nx)
    Nx = 1;
end

params_all = {'k_aKG_2HG_est', 'k_aKG_C1toC5', 'k_aKG_C5toC1', ...
    'R1_aKG_C1', 'R1_aKG_C5', 'R1_2HG', ...
    'S0_aKG_C1', 'S0_aKG_C5', 'S0_2HG'};%, ...
%    'Rinj', 'Tarrival', 'Tbolus'};
params_default_est = [0.01, 0.1, 1, ...
    1/30, 1/25, 1/25, 1/15, ...
    0, 0, 0] ;%, ...
%    0.1, 0, 8];
params_default_lb = [-Inf, -Inf, -Inf, ...
    1/50, 1/50, 1/50, 1/50, ...
    -Inf, -Inf, -Inf]; %, ...
%    0, -30, 0];
params_default_ub = [Inf, Inf, Inf, ...
    1/10, 1/10, 1/10, 1/5 , ...
    Inf, Inf, Inf]; %, ...
%    Inf 30 Inf];


if nargin < 5 || isempty(params_fixed)
    params_fixed = struct([]);
end

if nargin < 6 || isempty(params_est)
    params_est = struct([]);
end

% Supports up to 3 metabolic products (e.g. alanine, lactate, bicarb)
products_string = {'2HG'};

I_params_est = [];
for n = 1:length(params_all)
    if ~isfield(params_fixed, params_all(n))
        I_params_est = [I_params_est, n];
    end
end
Nparams_to_fit = length(I_params_est);

for n = 1:Nparams_to_fit
    param_names{n} = params_all{I_params_est(n)};

    if isfield(params_est, param_names{n})
        params_est_vec(n) = params_est.(param_names{n});
    else
        params_est_vec(n) = params_default_est(I_params_est(n));
    end
    if isfield(params_est, [param_names{n} '_lb'])
        params_lb(n) = params_est.([param_names{n} '_lb']);
    else
        params_lb(n) = params_default_lb(I_params_est(n));
    end
    if isfield(params_est, [param_names{n} '_ub'])
        params_ub(n) = params_est.([param_names{n} '_ub']);
    else
        params_ub(n) = params_default_ub(I_params_est(n));
    end
end


if nargin < 6 || isempty(noise_level)
    % no noise level provided, so use least-squares fit (best for Gaussian
    % zero-mean noise)
    fit_method = 'ls';
else
    % otherwise use maximum likelihood (good for Rician noise from
    % magnitudes)
    fit_method = 'ml';
end

if nargin < 7
    plot_flag = 0;
end

if plot_flag
    disp('==== Computing parameter map ====')
end

Sreshape = reshape(S, [prod(Nx), 2, Nt]);  % put all spatial locations in first dimension

[Sscale, Mzscale] = flips_scaling_factors(flips, Nt);

params_fit_vec = zeros([prod(Nx),Nparams_to_fit]);  objective_val = zeros([1,prod(Nx)]);
lb = zeros([prod(Nx),Nparams_to_fit]); ub = zeros([prod(Nx),Nparams_to_fit]); err = zeros([prod(Nx),Nparams_to_fit]);
Sfit = zeros([prod(Nx),1,Nt]); ufit = zeros([prod(Nx),Nt]);
Rsq = zeros([prod(Nx),1]); CHIsq = zeros([prod(Nx),1]);

for i=1:size(Sreshape, 1)
    % observed magnetization (Mxy)
    Mxy = reshape(Sreshape(i, :, :), [2, Nt]);
    
    if any(Mxy(:) ~= 0)

        if prod(Nx) > 1
            disp([num2str( floor(100*(i-1)/size(Sreshape, 1)) ) '% complete'])
        end


        % estimate state magnetization (MZ) based on scaling from RF pulses
        Mz = Mxy./Sscale(1:2,:);
        
        % option to propogate inputless model from various points in time
        Istart = 1;
        
        % fit to data
        % options = optimoptions(@fminunc,'Display','none','Algorithm','quasi-newton'); % not supported in Octave
        options = optimset('Display','none','Algorithm','quasi-newton');
        lsq_opts = optimset('Display','none','MaxIter', 500, 'MaxFunEvals', 500);
        
        switch(fit_method)
            case 'ls'
                obj = @(var) difference_inputless(var, params_fixed, TR, Mzscale, Sscale, Mz, Istart) ;  % perform least-squares in signal domain
                [params_fit_vec(i,:),objective_val(i),resid,~,~,~,J] = lsqnonlin(obj, params_est_vec, params_lb, params_ub, lsq_opts);
    
                if ~isOctave
                    % extract 95% confidence interval on lactate timecourse fitting
                    CI = nlparci(params_fit_vec(i,:),resid,'jacobian',J);
                    lb(i,:) = CI(:,1);
                    ub(i,:) = CI(:,2);
                    err(i,:) = CI(:,2)-CI(:,1);
                end
            case 'ml'
                obj = @(var) negative_log_likelihood_rician_inputless(var, params_fixed, TR, Mzscale, Mz, noise_level.*(Sscale).^2, Istart, Nmets);
                [params_fit_vec(i,:), objective_val(i)] = fminunc(obj, params_est_vec, options);
        end
        
        [Mzfit, ufit(i,:)] = trajectories_inputless(params_fit_vec(i,:), params_fixed, TR,  Mzscale, Mz(1,:), Istart);
        Mxyfit = Mzfit .* Sscale;
        % account for overlapping resonances
        Sfit(i,:,:) = Mxyfit(2,:)+Mxyfit(3,:);
        ufit(i,:) = ufit(i,:)  .* Sscale(1, :);
        
        % Note that Sfit only inlcudes products signals, not pyruvate,
        % hence the difference in indexing here and in plots below
        Rsq(i,1) = 1 - sum( (Sreshape(i,2,:)-Sfit(i,:,:)).^2 ,3 ) ...
            ./ sum( (Sreshape(i,2,:) - repmat(mean(Sreshape(i,2,:),3),[1 1 Nt])).^2, 3);
        % chi squared distance - also pdist2 in Octave
        CHIsq(i,1) = sum( (Sreshape(i,2,:)-Sfit(i,:,:)).^2 ./ ...
            (Sreshape(i,2,:)+Sfit(i,:,:)) ,3) / 2;
        
        if plot_flag
            % plot of fit for debugging
            figure(99)
            subplot(2,1,1)
            plot(t, Mz, t, Mzfit,'--', t, ufit(i,:)./ Sscale(1, :), 'k:')
            xlabel('time (s)')
            ylabel('state magnetization (au)')
            subplot(2,1,2)
            plot(t, Mxy, t, squeeze(Sfit(i,:,:)),'--', t, ufit(i,:), 'k:')
            xlabel('time (s)')
            ylabel('signal (au)')
            
            fit_results_string = [];
            for n = 1:Nparams_to_fit
                fit_results_string = [fit_results_string, param_names{n} ' = ' num2str(params_fit_vec(i,n),2) ' '];
            end            
            title(fit_results_string)
            disp(fit_results_string)
            
%             products_legend{1} = 'pyruvate';
%             for n = 1:Nmets-1
%                 products_legend{n+1} = products_string{n};
%                 products_legend{n+Nmets} = [products_string{n} ' fit'];
%             end    
%             products_legend{Nmets*2} = 'input estimate';
%             legend( products_legend)
            drawnow, pause(0.5)
        end
    end
end

error_metrics=struct('objective_val', objective_val);
% for n = 1:length(products_string)
%     error_metrics.(products_string{n}).Rsq = Rsq(:,n);
%     error_metrics.(products_string{n}).CHIsq = CHIsq(:,n);
% end

params_fit = struct([]);
for n = 1:Nparams_to_fit
    params_fit(1).(param_names{n})= params_fit_vec(:,n);
    if strcmp(fit_method, 'ls') && ~isOctave
        error_metrics.(param_names{n}).lb = lb(:,n);
        error_metrics.(param_names{n}).ub = ub(:,n);
        error_metrics.(param_names{n}).err = err(:,n);
    end
end

if length(Nx) > 1
    for n = 1:Nparams_to_fit
        params_fit.(param_names{n}) = reshape(params_fit.(param_names{n}), Nx);
        if strcmp(fit_method, 'ls') && ~isOctave
            error_metrics.(param_names{n}).lb = reshape(error_metrics.(param_names{n}).lb, Nx);
            error_metrics.(param_names{n}).ub = reshape(error_metrics.(param_names{n}).ub, Nx);
            error_metrics.(param_names{n}).err = reshape(error_metrics.(param_names{n}).err, Nx);
        end
    end
    
    Sfit = reshape(Sfit, [Nx, 1, Nt]);
    ufit = reshape(ufit, [Nx, Nt]);

    error_metrics.objective_val = reshape(error_metrics.objective_val, Nx);
    for n = 1:length(products_string)
        error_metrics.(products_string{n}).Rsq = reshape(error_metrics.(products_string{n}).Rsq, Nx);
        error_metrics.(products_string{n}).CHIsq =  reshape(error_metrics.(products_string{n}).CHIsq, Nx);
    end
    disp('100 % complete')
end

end

function diff_products = difference_inputless(params_fit, params_fixed, TR, Mzscale, Sscale, Mz, Istart)
Mzfit = trajectories_inputless(params_fit, params_fixed, TR,  Mzscale, Mz(1,:), Istart) ;
Mxyfit = Mzfit .* Sscale;
% account for overlapping resonances
Mxyfit_overlapped = [Mxyfit(1,:); Mxyfit(2,:)+Mxyfit(3,:)];

temp_diff = Mz.*Sscale(1:2,:) - Mxyfit_overlapped; % compute difference in the signal (Mxy) domain
diff_products = temp_diff(2,:); % only fitting allowed at metabolic product resonance
diff_products = diff_products(:);
end

function [ l1 ] = negative_log_likelihood_rician_inputless(params_fit, params_fixed, TR, Mzscale, Mz, noise_level, Istart, Nmets)
%FUNCTION NEGATIVE_LOG_LIKELIHOOD_RICIAN Computes log likelihood for
%    compartmental model with Rician noise
% noise level is scaled for state magnetization (Mz) domain

%https://doi.org/10.1109/42.712125

N = size(Mzscale,2);

% compute trajectory of the model with parameter values
Mzfit = trajectories_inputless(params_fit, params_fixed, TR,  Mzscale, Mz(1,:), Istart) ;

% compute negative log likelihood
l1 = 0;
for t = 1:N
    for k = 2:Nmets
        l1 = l1 - (...
            log(Mz(k, t)) - log(noise_level(k,t)) ...
            - (Mz(k, t)^2 + Mzfit(k, t)^2)/(2*noise_level(k,t)) ...
            + Mz(k, t)*Mzfit(k, t)/noise_level(k,t) ...
            + log(besseli(0, Mz(k, t)*Mzfit(k, t)/noise_level(k,t), 1))...
            );
    end
end
end

function [Mz_all, u] = trajectories_inputless( params_fit, params_fixed, TR, Mzscale , Mz_pyr, Istart )
% Compute product magnetizations using a uni-directional two-site model
% Uses substrate magnetization measurements, estimated relaxation and
% conversion rates

if nargin < 6
    Istart = 1;
end


Nmets = size(Mzscale,1); N = size(Mzscale,2);
Mz_all = zeros(Nmets, N);
u = zeros(1,N);

params_all = {'k_aKG_2HG', 'k_aKG_C1toC5', 'k_aKG_C5toC1', ...
    'R1_aKG_C1', 'R1_aKG_C5', 'R1_2HG', ...
    'S0_aKG_C1', 'S0_aKG_C5', 'S0_2HG'};

nfit = 0;
for n = 1:length(params_all)
    if isfield(params_fixed, params_all(n))
        eval([params_all{n} '= params_fixed.(params_all{n});']);
    else
        nfit = nfit+1;
        eval([params_all{n} '= params_fit(nfit);']);
    end
end

Mz_all(1,:) = Mz_pyr; % aKG C1 signal
%Mz_all(1,Istart) = S0_aKG_C1;
Mz_all(2,Istart) = S0_aKG_C5;
Mz_all(3,Istart) = S0_2HG;

A = [-R1_aKG_C1-k_aKG_C1toC5-k_aKG_2HG, +k_aKG_C5toC1, 0
    +k_aKG_C1toC5, -R1_aKG_C5-k_aKG_C5toC1, 0
    +k_aKG_2HG, 0, -R1_2HG];

k_substrate = R1_aKG_C1+k_aKG_2HG;
ratio_aKG_C1toC5 = k_aKG_C5toC1/k_aKG_C1toC5;

for It=Istart:N-1
    
    Mz_init = Mz_all(:,It) .* Mzscale(:, It);
    
    % estimate input, assuming this is constant during TR interval and no
    % conversion into substrate (not true fo aKG model)
    % some hacks to try and account for C5 too
    u(It) = ( Mz_pyr(It+1)*(1+1/ratio_aKG_C1toC5) - (Mz_init(1)+Mz_init(2))*exp((-k_substrate)*TR) ) * (k_substrate) / (1 - exp((- k_substrate)*TR));
    
    % assume input for C5 resonance as well
    xstar = - inv(A)*[u(It)/(1+1/ratio_aKG_C1toC5),u(It)/(1+ratio_aKG_C1toC5),0].';
    
    % solve next time point under assumption of constant input during TR
    Mz_all(:,It+1) = xstar + expm(A*TR) * (Mz_init - xstar);
    
    
end

% reverse in time 
for It=Istart:-1:2
    
    Mz_init = Mz_all(:,It);
    
    % estimate input, assuming this is constant during TR interval
    % This calculation could be improved for noise stability?
    u(It-1) = ( Mz_pyr(It-1)*Mzscale(1,It-1) - Mz_init(1)*exp((- k_substrate)*-TR) ) * (k_substrate) / (1 - exp((- k_substrate)*-TR));
    
    xstar = - inv(A)*[u(It-1),u(It-1)*k_aKG_C1toC5/k_aKG_C5toC1,0].';
    
    % assume input for C5 resonance as well
    % solve previous time point under assumption of constant input during TR
    Mz_plus = xstar + expm(A*-TR) * (Mz_init - xstar);
    
    
    Mz_all(:,It-1) = Mz_plus ./ Mzscale(:, It-1);
    
    
end


end
