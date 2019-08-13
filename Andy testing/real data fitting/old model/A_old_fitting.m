% Andy's comment:
% 	This file is a modified version of Prof. Larson's test_fit_kPL_fcn.m
%   This file is for testing over the data collected by Renuka Sriram.
% 	Thanks for all the help from Shuyu Tang
% 	Script for testing fit_kPL kinetic model fitting functions

clear all;
close all;
clc;

%%
data_dir = './Andy testing/data/Andy_data/with_vexel_mat/';
fitted_dir='./Andy testing/data/perfused_fitted/';
[filenames,files_num] = A_get_filenames2(data_dir,'.mat');
plot_flag=0;

tumor_kpl=zeros(files_num,6);

% choose fitting function to test
fit_function = @fit_kPL;
plot_fits = 0;

for file_index=1:files_num % loop for one mat file
	clearvars -except data_dir fitted_dir filenames files_num file_index plot_flag fit_function plot_fits tumor_kpl
	% file_index=1;
    
	% clear filename,Mxy,flips,VIF,t,TR,Tin,std_noise,mean_noise
	load([char(filenames(file_index))])
	if plot_flag==1
		figure
			subplot(221) , plot(t, squeeze(flips(1, : )) * 180 / pi)
			title('Pyruvate flips')
			subplot(222) , plot(t, squeeze(flips(2, : )) * 180 / pi,'--o');
			title('Lactate flips')
			% plot pyr and lac
			subplot(2,2,3) , plot(t, squeeze(Mxy(1, : , 1)))
			hold on
			plot(t, squeeze(Mxy(1, :,2 )),':')
			plot(t, squeeze(Mxy(1, :,3 )),'-')
			plot(t,squeeze(VIF(1,:)),'-*')
			title(['Pyruvate  ',filename(1:10)])
			legend('tumor','cont','noise','VIF pyr')
			subplot(2,2,4); hold on;
			plot(t, squeeze(Mxy(2, :,1 )))
			plot(t, squeeze(Mxy(2, :,2 )),':')
			plot(t, squeeze(Mxy(2, :,3 )),'-')
			plot(t,squeeze(VIF(2,:)),'-*')
			title('Lactate')
			legend('tumor','cont','noise','VIF lac')
			% legend('Pyruvate tumor','Lactate tumor','Pyruvate control','Lactate control','Pyruvate noise','Lactate noise')
	end
	std_noise=std_noise*sqrt(pi/2);

	% initial parameter guesses
	R1P_est = 1/25; R1L_est = 1/25; kPL_est = .9;  kve_est = 0.02; vb_est = 0.1;
	R1P_est = 1/25; R1L_est = 1/25; kPL_est = 0.2;  kve_est =0.02; vb_est = 0.09; vif_est=1;

	% kve_est = kve; vb_est = vb;kve = 0.05; vb = 0.1;


	% Test fitting - fit kPL only
	% disp('Fitting kPL, with fixed relaxation rates:')
	% disp('Fixing relaxation rates improves the precision of fitting, but potential')
	% disp('for bias in fits when incorrect relaxation rate is used')
	% disp(' ')

	clear params_fixed params_est params_fit params_fitn_complex params_fitn_mag
	params_fixed.R1P = R1P_est; params_fixed.R1L = R1L_est;
	% params_fixed.kve = kve_est; params_fixed.vb = vb_est;
	% params_est.VIFscale = 1;
	params_est.kPL = kPL_est;
	% params_est.S0_P=0;
	params_est.S0_L=1;
	% add IV function

	for Dtype = 1:3 % tumor control noise
	    % no noise
	    [params_fit(:,Dtype) Sfit(1:size(Mxy,2),  Dtype)] = fit_function(Mxy(:,:,Dtype), TR, flips(:,:), params_fixed, params_est, [], plot_fits);
	    
	    % % add noise
	    % [params_fitn_complex(:,Dtype) Snfit_complex(1:2,1:size(S,2),  Dtype)] = fit_function(Sn(:,:,Dtype), TR, flips(:,:,Dtype), params_fixed, params_est, [], plot_fits);

	    % magnitude fitting with noisec
	    [params_fitn_mag(:,Dtype) Snfit_mag(1:size(Mxy,2),  Dtype)] = fit_function(Mxy(:,:,Dtype), TR, flips(:,:),params_fixed, params_est, std_noise, plot_fits);
	end
	%
	flip_descripton{1}='tumor';
	flip_descripton{2}='control';
	flip_descripton{3}='noise';
	description_array = [repmat('    ',3,1),  char(flip_descripton(:))];


	tumor_kpl(file_index,:)=[getfield(struct2table(params_fit),'kPL')',getfield(struct2table(params_fitn_mag),'kPL')'];
	tumor_kpl

	disp('---------------------------------------------------');
	% disp(sprintf('Input R1 = %f (pyr) %f (lac), kPL = %f', R1P_est, R1L_est, kPL_est))
	disp(filename)
	disp('Noiseless fit results:')
	disp(['kPL  = ']); disp([num2str(getfield(struct2table(params_fit),'kPL')), description_array])
	disp('Noisy magnitude fit results:')
	disp(['kPL  = ']); disp([num2str(getfield(struct2table(params_fitn_mag),'kPL')), description_array])


	titles={'tumor','cont', 'noise'};
if plot_flag==1
    fig=figure(5);
    set(fig, 'units','normalized', 'outerposition', [0.2 0.1 0.6 0.8], 'Name', 'Data fitting');
    % set( fig, 'units','normalized', 'outerposition', [0.2 0.1 2 2], 'Name', 'Data fitting');
	subplot(files_num,4,1+(file_index-1)*4)
	plot(t, squeeze(Mxy(1,:,:)))
	hold on;
	plot(t, squeeze(Sfit(:,1:2)),':*')
	plot(t, squeeze(Snfit_mag(:,1:2)),'--s')
	legend('ori tumor','ori cont','ori noise','no-noi tumor','no-noi cont','noi-f tumor','noi-f cont','Location','northeastoutside')
	title(['Pyruvate signals ',filename])
	subplot(files_num,4,2+(file_index-1)*4) 
	hold on;
	plot(t, squeeze(Mxy(2,:,:)))
	plot(t, squeeze(Sfit(:,1:2)),':*')
	plot(t, squeeze(Snfit_mag(:,1:2)),'--s')
	legend('ori tumor','ori cont','ori noise','no-noi tumor','no-noi cont','noi-f tumor','noi-f cont','Location','northeastoutside')
	title('Lac signals')

	
	subplot(files_num,4,3+(file_index-1)*4)
	hold on;
	plot(t, squeeze((Sfit(:,1:2)-squeeze(Mxy(1,:,1:2)))./(squeeze(Mxy(1,:,1:2)))),':*')
	plot(t, squeeze((Snfit_mag(:,1:2)-squeeze(Mxy(1,:,1:2)))./squeeze(Mxy(1,:,1:2))),'--s')
	legend('no-noi tumor','no-noi cont','noi-f tumor','noi-f cont','Location','northeastoutside')
	ylim([-1 1])
	title('Pyruvate ERROR percentage')
	subplot(files_num,4,4+(file_index-1)*4) 
	hold on;
	plot(t, squeeze((Sfit(:,1:2)-squeeze(Mxy(2,:,1:2)))./squeeze(Mxy(2,:,1:2))),':*')
	plot(t, squeeze((Snfit_mag(:,1:2)-squeeze(Mxy(2,:,1:2)))./squeeze(Mxy(2,:,1:2))),'--s')
	legend('no-noi tumor','no-noi cont','noi-f tumor','noi-f cont','Location','northeastoutside')
	title('Lac NOISE percentage')
    ylim([-1 1])
end
end
%%
titles={'no-noi tumor','no-noi cont','no-noi noise', 'noisy tumor','noisy cont','noisy noise'};
disp(titles)
old_kpl=tumor_kpl
save([fitted_dir,'old_model'],'old_kpl')