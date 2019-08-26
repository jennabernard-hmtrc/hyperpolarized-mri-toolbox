% Script for testing fit_kPL kinetic model fitting functions

clear all

% choose fitting function to test
fit_function = @fit_kPL;
plot_fits = 1;

% Test values
Tin = 0; Tacq = 48; TR = 3; N = Tacq/TR;
R1P = 1/25; R1L = 1/25; kPL = 0.05; std_noise = 0.01;
input_function = zeros(1,N);

input_condition = 1; % choose from various simulated starting conditions
switch input_condition
    case 1
        % gamma variate input function - most realistic
        Tarrival = 0;  Tbolus = 12;
        input_function = realistic_input_function(N, TR, Tarrival, Tbolus);
        Mz0 = [0,0]; 
    case 2
        % boxcar input function
        Tbolus = 12;  Tarrival = 0;
        Ibolus = [1:round(Tbolus/TR)] + round(Tarrival/TR);
        Rinj = 1/Tbolus; % normalize for a total magnetization input = 1
        Mz0 = [0,0]; input_function(Ibolus) =  Rinj*TR;
    case 3
        Mz0 = [1.5,0]; % no input function
    case 4
        Tin = 6; Mz0 = Tin; % no input function, delayed start
end

% Test over multiple combinations of flip angle schemes
flips(1:2,1:N,1) = ones(2,N)*30*pi/180;  flip_descripton{1} = 'constant, single-band';
flips(1:2,1:N,2) = repmat([20;35]*pi/180,[1 N]);  flip_descripton{2} = 'constant, multi-band';
k12 = 0.05; % for variable flip angle designs
flips(1:2,1:N,3) = [vfa_const_amp(N, pi/2, exp(-TR * ( k12))); ... % T1-effective pyruvate variable flip angles
    vfa_opt_signal(N, exp(-TR * ( R1L)))]; % max lactate SNR variable flip angle
flip_descripton{3} = 'max lactate SNR variable flip, multi-band';
% flips(1:2,1:N,4) = repmat(vfa_const_amp(N, pi/2), [2,1]);  % RF compensated variable flip angle
% flips(1:2,1:N,5) = [vfa_const_amp(N, pi/2, exp(-TR * ( k12))); ... % T1-effective variable flip angle
%     vfa_const_amp(N, pi/2, exp(-TR * ( - k12)))];
% flips(1:2,1:N,6) = [vfa_const_amp(N, pi/2, exp(-TR * (k12))); ... % saturation recovery
%     ones(1,N)*pi/2];
N_flip_schemes = size(flips,3);

t = [0:N-1]*TR + Tin;

figure
subplot(121) , plot(t, squeeze(flips(1,:,:))*180/pi)
title('Pyruvate flips')
subplot(122) , plot(t, squeeze(flips(2,:,:))*180/pi)
title('Lactate flips')
legend(flip_descripton)

flip_description_array = [repmat('    ',N_flip_schemes,1),  char(flip_descripton(:))];

% generate simulated data
noise_S = randn([2 N])*std_noise;  % same noise for all flip schedules
for Iflips = 1:N_flip_schemes
    [Mxy(1:2, 1:N, Iflips), Mz] = simulate_Nsite_model(Mz0, [R1P R1L], [kPL 0], flips(:,:,Iflips), TR, input_function);
    % add noise
    Sn(1:size(Mxy,1), 1:size(Mxy,2),  Iflips) = Mxy(:,:,Iflips) + noise_S;
end

% initial parameter guesses
R1P_est = 1/25; R1L_est = 1/25; kPL_est = .02;

%% Test fitting - fit kPL only
disp('Fitting kPL, with fixed relaxation rates:')
disp('Fixing relaxation rates improves the precision of fitting, but potential')
disp('for bias in fits when incorrect relaxation rate is used')
disp(' ')

clear params_fixed params_est params_fit params_fitn_complex params_fitn_mag
params_fixed.R1P = R1P_est; params_fixed.R1L = R1L_est;
params_est.kPL = kPL_est;

for Iflips = 1:N_flip_schemes
    % no noise
    [params_fit(:,Iflips) Sfit(1:size(Mxy,2),  Iflips)] = fit_function(Mxy(:,:,Iflips), TR, flips(:,:,Iflips), params_fixed, params_est, [], plot_fits);
    
    % add noise
    [params_fitn_complex(:,Iflips) Snfit_complex(1:size(Mxy,2),  Iflips)] = fit_function(Sn(:,:,Iflips), TR, flips(:,:,Iflips), params_fixed, params_est, [], plot_fits);
    
    % magnitude fitting with noise
    [params_fitn_mag(:,Iflips) Snfit_mag(1:size(Mxy,2),  Iflips)] = fit_function(abs(Sn(:,:,Iflips)), TR, flips(:,:,Iflips),params_fixed, params_est, std_noise, plot_fits);
end

disp(sprintf('Input R1 = %f (pyr) %f (lac), kPL = %f', R1P, R1L, kPL))
disp('Noiseless fit results:')
disp(['kPL  = ']); disp([num2str(struct2array(params_fit).'), flip_description_array])
disp('Noisy complex fit results:')
disp(['kPL  = ']); disp([num2str(struct2array(params_fitn_complex).'), flip_description_array])
disp('Noisy magnitude fit results:')
disp(['kPL  = ']); disp([num2str(struct2array(params_fitn_mag).'), flip_description_array])

figure
subplot(121) , plot(t, squeeze(Sn(1,:,:)))
title('Pyruvate signals')
subplot(122) , plot(t, squeeze(Sn(2,:,:)))
hold on, plot(t, squeeze(Snfit_complex(:,:)),':')
plot(t, squeeze(Snfit_mag(:,:)),'--')
title('kPL fit: Lactate signals and fits (dots=complex fit, dashed=magnitude)')
legend('constant','multiband', 'multiband variable flip')

disp('Press any key to continue')
disp(' ')

pause

%% Test fitting - fit kPL and T1 of lactate
disp('Fitting kPL and lactate T1:')
disp('Fitting both parameters leads to increases in variability, which can be')
disp('alleviated to some extent by constraints on the parameter values')
disp('(Pyruvate T1 values have very small effect on this fitting approach)')
disp(' ')

% Fitting both kPL and relaxation rate of lactate
clear params_fixed params_est params_fit params_fitn_complex params_fitn_mag
params_fixed.R1P = R1P_est;
params_est.kPL = kPL_est; params_est.R1L = R1L_est;
% set constraints on lactate T1:
params_est.R1L_lb = 1/40;
params_est.R1L_ub = 1/15;

for Iflips = 1:N_flip_schemes
    % no noise
    [params_fit(:,Iflips) Sfit(1:size(Mxy,2),  Iflips)] = fit_function(Mxy(:, :, Iflips), TR, flips(:,:,Iflips), params_fixed, params_est, [], plot_fits);
    
    % noise, complex-valued fitting
    [params_fitn_complex(:,Iflips) Snfit_complex(1:size(Mxy,2),  Iflips)] = fit_function(Sn(:,:,Iflips), TR, flips(:,:,Iflips), params_fixed, params_est, [], plot_fits);
    
    % magnitude fitting with noise
    [params_fitn_mag(:,Iflips) Snfit_mag(1:size(Mxy,2),  Iflips)] = fit_function(abs(Sn(:,:,Iflips)), TR, flips(:,:,Iflips),params_fixed, params_est, std_noise, plot_fits);
end

disp(sprintf('Input R1 = %f (pyr) %f (lac), kPL = %f', R1P, R1L, kPL))
disp('Noiseless fit results:')
disp(['kPL         R1L   = ']); 
disp([num2str(reshape(struct2array(params_fit), 2, N_flip_schemes).'), flip_description_array])
disp('Noisy complex fit results:')
disp(['kPL         R1L   = ']); disp([num2str(reshape(struct2array(params_fitn_complex), 2, N_flip_schemes).'), flip_description_array])
disp('Noisy magnitude fit results:')
disp(['kPL         R1L   = ']); disp([num2str(reshape(struct2array(params_fitn_mag), 2, N_flip_schemes).'), flip_description_array])

figure
subplot(121) , plot(t, squeeze(Sn(1,:,:)))
title('Pyruvate signals')
subplot(122) , plot(t, squeeze(Sn(2,:,:)))
hold on, plot(t, squeeze(Snfit_complex(:,:)),':')
plot(t, squeeze(Snfit_mag(:,:)),'--')
title('kPL+R1L fit: Lactate signals and fits (dots=complex fit, dashed=magnitude)')
legend('constant','multiband', 'multiband variable flip')

