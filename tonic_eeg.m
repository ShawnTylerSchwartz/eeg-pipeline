%% 
%% EEG pipeline to extract trial-level tonic posterior alpha power 
%% Shawn T. Schwartz <stschwartz@stanford.edu> 2022
%% 
%% Adapted from Madore et al. (2020, Nature)
%%

function tonic_eeg(step)

%% SETUP (customize relevant paths/details here)
basedir = '/Users/shawn/Developer/repos/eeg-pipeline/';
scriptdir = basedir;
experiment_name = 'spindrift';
datadir = ['../../../Dropbox/Research/Stanford/wagner-lab/data_archive/', experiment_name, '/memory/include/'];
subjidsfname = 'subject_ids_to_preproc.txt';
band = 'alpha';
EVENT_TAG = {'retm'};
TONIC_EPOCH_TIMEBIN = [-1 0];
ERP_EPOCH_TIMEBIN = [-0.2 1];
ERP_BASELINE_TIMEBIN = [-200 0];
TRIALS_PER_RUN = 32;

%% load environment
addpath(genpath(scriptdir));
addpath(datadir);
group = importdata([datadir, subjidsfname]); % one subject name per line

if nargin < 1
    step = 'preproc';
end

%% Naming key:
% bandpass filter -> f
% reject bad channels -> b
% manually prune -> p
% average rereference -> r
% center -> c
% epoch -> e
% concatenated runs -> cat

%% begin iterating over EEG data for each subject
for subj = 1:length(group)
    %% load eeg datasets

    if ~strcmp(step, 'manrej')
        [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
    end

    suffix = ['_', experiment_name, '_'];

    subid = sprintf('%s', group{subj});
    fprintf(['\n\n',subid,'\n\n']);

    filepath = [datadir, subid, '/eeg/ret/raw/'];

    if subj > 1
        cd(basedir);
    end

    cd(filepath);

    runs = [0 1 2 3 4 5];

    n_runs = size(runs, 2);


    %% EEG PREPROCESSING STEP
    if strcmp(step, 'preproc')
        %% eeg preprocessing

        reject_indices = {};
        all_reject = [];

        for i = 1:n_runs
            %% Setup
            r = runs(i);
            curr_suffix = suffix;
    
            %% Load .raw EGI file
            % run_file = [datadir, subid, '/eeg/ret/raw/', subid, '_test', num2str(r), '.raw'];
            run_file = [pwd, '/', subid, '_test', num2str(r), '.raw'];
            disp(run_file);
            % EEG = pop_readegi(run_file, [], [], 'auto');
            EEG = pop_readegi(run_file, [], [], ['../../../../../../../../../../../../..', basedir, 'montage/GSN-HydroCel-128.sfp']);
    
            %% Load channel locations
            EEG = pop_chanedit(EEG, 'load', {[basedir, 'montage/GSN-HydroCel-128.sfp'] 'filetype' 'autodetect'});
    
            %% Remove useless channels (cheeks, eyes)
            channels_to_toss = [127, 126, 17, 25, 21, 22, 15, 14, 9, 8, ...
                1, 32, 125, 128, 119, 120, 113, 114, 121, 49, 48, 43, 44, 38]; 
            
            EEG = pop_select(EEG, 'nochannel', channels_to_toss);
            suffix = [suffix, 'b'];

            %% Decimate from 1000Hz to 100Hz
            EEG = pop_resample(EEG, 100);

            %% Bandpass filter
            fprintf(['\nFiltering subject ', subid, ', run ', num2str(r), '\n']);

            %% Hamming windowed sinc FIR filter
            EEG = pop_eegfiltnew(EEG, .1); % high pass filter
            EEG = pop_eegfiltnew(EEG, [], 30); % low pass filter

            %% Run BLINKER to insert blink events
            fprintf('Detecting blinks with BLINKER... ');

            fieldList = {'maxFrame', 'leftZero', 'rightZero', 'leftBase', 'rightBase', ...
                'leftZeroHalfHeight', 'rightZeroHalfHeight'};

            [EEG, com, blinks, blinkFits, blinkProperties, blinkStatistics, params] = pop_blinker(EEG, struct());

            if ~isempty(blinkStatistics)
                % save blinkinfo data
                blinkInfo = struct();
                blinkInfo.blinks = blinks;
                blinkInfo.blinkFits = blinkFits;
                blinkInfo.blinkProperties = blinkProperties;
                blinkInfo.blinkStatistics = blinkStatistics;
                blinkInfo.blinkSignal = [];
                blinkInfo.custom = [];
                blinkInfo.custom.blinkChannel = '';
    
                if isnan(blinks.usedSignal)
                    warning('%s: does not have a blink signal', num2str(r))
                else
                    blinkInfo.custom.blinkChannel = EEG.chanlocs(abs(blinks.usedSignal)).labels;
                    if ~isempty(fieldList)
                        [EEG, blinkSignal] = addBlinkEvents(EEG, blinks, blinkFits, blinkProperties, fieldList);
                        blinkInfo.blinkSignal = blinkSignal;
                    end
                end
            
                fname = sprintf('test%s_blinkInfo.mat', num2str(r));
                save(fname, 'blinkInfo');

                %% Remove eye artifact and blink activity from time-domain (uses EyeCatch)
                fprintf('Removing artifacts using EyeCatch...');
                icatype = 'runica';
                regressBlinkEvents = false;
                regressBlinkSignal = false;
                [EEG, removalInfo] = removeEyeArtifactsLARG(EEG, blinkInfo, ...
                                        icatype, regressBlinkEvents, regressBlinkSignal);
                EEG.icaact = [];
                save(sprintf('test%s_removalInfo.mat', num2str(r)), 'removalInfo');
            end
    
            suffix = [suffix, 'f'];
    
            %% Save data
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                [subid, '_test', num2str(r), suffix], 'savenew', [subid, '_test', num2str(r), ...
                suffix, '.set'], 'overwrite', 'on', 'gui', 'off');
    
            %% Find bad channels to remove
            [~, indelec] = pop_rejchanspec(EEG, 'stdthresh', [-3, 3]);
            reject_indices{r+1, 1} = indelec;
            all_reject = [all_reject, reject_indices{r+1, 1}];
    
            %% Reset
            suffix = curr_suffix;
        end
    
        suffix = [suffix, 'bf'];
    
        %% Remove bad channels from all runs
        for i = 1:n_runs
            %% Setup
            r = num2str(runs(i));
            curr_suffix = suffix;
            file = [subid, '_test', r, suffix, '.set'];
    
            %% Load in dataset
            EEG = pop_loadset('filename', file);
            EEG = pop_select(EEG, 'nochannel', all_reject);
            suffix = [suffix, 'b'];
    
            %% Save out indices -- reject all for each run (union)
            save('rejected_channels', 'reject_indices');
    
            %% Save out data
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                [subid, '_test', num2str(r), suffix], 'savenew', [subid, '_test', r, ...
                suffix, '.set'], 'overwrite', 'on', 'gui', 'off');
    
            %% Reset
            suffix = curr_suffix;
        end
    
        %% Setup for post pre-processing
        suffix = [suffix, 'bfb'];
        suffix = ['_', experiment_name, '_bfb'];
    
        %% Epoch dataset
        for i = 1:n_runs
            %% Setup
            r = num2str(runs(i));
            file = [subid, '_test', r, suffix];
    
            %% Load in dataset
            EEG = pop_loadset([file, '.set']);
            [ALLEEG] = eeg_store(ALLEEG, EEG, i);
        end
    
        EEG = pop_mergeset(ALLEEG, 1:n_runs, 0);
        EEG = pop_epoch(EEG, EVENT_TAG, TONIC_EPOCH_TIMEBIN, 'newname', 'epochs', 'epochinfo', 'yes');
        pop_saveset(EEG, 'filename', 'merged_raw_epochs');
    
    end


    %% EEG MANUAL ARTIFACT REJECTION STEP
    %% Steps for manual rejection of epochs
    % The pop_eegplot() function doesn't return anything or store the
    % changes to the current EEG set when run from the script, so it isn't
    % useful from an automated standpoint. Nonetheless, here's how to run
    % this portion:
    %
    % Step 1) Run the first part of this script like normal for all
    % subject ids: tonic_eeg('preproc')
    %
    % Step 2) Once all subjects have been run and preprocessed, then it's
    % time for (this) non-automated portion :(
    %   2.1) Change current directory to each subject's directory (you can
    %   use the "Current Folder" / file chooser above (or do this
    %   programmatically)
    %   2.2) Copy and paste everything within the block below (NOT
    %   INCLUDING THE "if strcmp(step, 'manrej')" / "end" lines) into the
    %   Command Window below
    %   2.3) Manually select the bad epochs with extreme values and change 
    %   window scale to '79':
    %   "As with continuous data, it is possible to use EEGLAB to reject
    %   epoched data simply by visual inspection. To do so, press the
    %   Scroll data button on the top of the interactive window. A
    %   scrolling window will pop up. Change the scale to ‘79’. Epochs are
    %   shown delimited by blue dashed lines and can be selected/deselected
    %   for rejection simply by clicking on them. Rejecting parts of an
    %   epoch is not possible." (from:
    %   https://eeglab.org/tutorials/misc/Rejecting_Artifacts_Legacy_Menus.html#:~:text=Rejecting%20epochs%20by%20visual%20inspection,the%20scale%20to%20'79'.)
    %   2.4) Click "UPDATE MARKS", and then the necessary CSV file with
    %   rejected epoch indices will be saved
    %   2.5) Now, after doing this for all subjects (ensuring that there's
    %   a "prestimret_rejected_epochs.csv" file in every subject folder
    %   unique to each subjects' rejected epochs, then run
    %   "tonic_eeg('filter')" which will take those rejected epochs
    %   into account when pulling out alpha bands/ERPs. **If no
    %   "prestimret_rejected_epochs.csv" file exists, then I made it assume
    %   that all epochs are good and it won't crash but instead run
    %   everything as if no epochs were rejected (i.e., like a csv file
    %   full of 0s for all epoch rejected indices)** This filter stage will
    %   subsequently output a file with the exact trial numbers
    %   corresponding to each column in the alpha band/ERP files to be
    %   appended for post hoc analyses of the processed EEG data
    %
    % -- Shawn, 06/07/2022
    if strcmp(step, 'manrej')
        clear;
        [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
        file_to_load = 'merged_raw_epochs.set';
        EEG = pop_loadset(file_to_load);
        pop_eegplot(EEG, 1, 1, 0);
        uiwait();
        rejected_trials = EEG.reject.rejmanual;
        rejected_trials = rejected_trials';
        csvwrite('prestimret_rejected_epochs.csv', rejected_trials);
    end


    %% EEG BAND FILTERING STEP
    if strcmp(step, 'filter')
        %% Setup
        suffix = ['_', experiment_name, '_bfb'];
        total_trials = [1:(length(runs)*TRIALS_PER_RUN)];

        %% EPOCH REMOVAL LOADING STEP
        % bring in rejected_epochs.csv file
        if exist('prestimret_rejected_epochs.csv', 'file')
            bad_prestim_epochs = csvread('prestimret_rejected_epochs.csv');
        else
            bad_prestim_epochs = zeros(length(runs)*TRIALS_PER_RUN, 1);
        end

        keep_these_trials = [];
        for ii = 1:length(total_trials)
            if bad_prestim_epochs(ii) == 0
                keep_these_trials = [keep_these_trials, total_trials(ii)];
            end
        end

        csvwrite([subid, '_prestimret_trials.csv'], keep_these_trials');

        %% FILTER STEP
        for i = 1:n_runs
            %% Setup
            r = num2str(runs(i));
            currsuffix = suffix;

            %% Average Rereference by run
            % Load manually inspected set
            file = [subid, '_test', r, suffix, '.set'];
            EEG = pop_loadset('filename', file);
            EEG = pop_reref(EEG, []);

            %% Save
            suffix = [suffix, 'r'];
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                [subid, '_test', r, '_rereferenced'], 'savenew', [subid, '_test', r, suffix, '.set'], ...
                'overwrite', 'on', 'gui', 'off');

            %% Reset
            suffix = currsuffix;
        end

        suffix = [suffix, 'r'];

        PAF = 10;

        %% Compute instantaneous power
        for i = 1:n_runs
            %% Setup
            r = num2str(runs(i));

            %% Load dataset
            EEG = pop_loadset('filename', [subid, '_test', r, suffix, '.set']);

            %% Compute
            EEG_power = comp_power_PAF(EEG, band, PAF);

            %% Epoch prestimulus
            EEG = EEG_power;

            %% Center by run
            run_chan_means = mean(EEG.data, 2);
            save([subid, '_test', r, '_', band, '_chan_means'], 'run_chan_means');

            %% Epoch: 1s prestim
            EEG = pop_epoch(EEG, EVENT_TAG, TONIC_EPOCH_TIMEBIN, 'newname', ...
                [subid, '_test', num2str(r), '_prestim_e'], 'epochinfo', 'yes');

            %% Save out epoched data
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                                [subid, '_test', num2str(r), '_', band, '_prestim'], 'savenew', ...
                                [subid, '_test', r, suffix, 'e_', band, '_prestim.set'], ...
                                'overwrite', 'on', 'gui', 'off');
        end

        %% Concatenate prestim runs
        for i = 1:n_runs
            %% Setup
            r = runs(i);

            %% Load the epoched sets
            EEG = pop_loadset('filename', ...
                [pwd, '/', subid, '_test', num2str(r), suffix, 'e_', band, '_prestim.set']);
    
            [ALLEEG] = eeg_store(ALLEEG, EEG, i);
        end

        %% Merge sets
        EEG = pop_mergeset(ALLEEG, 1:n_runs, 0);

        %% Remove bad epochs
        bad_epochs = bad_prestim_epochs;
        EEG = pop_rejepoch(EEG, bad_epochs, 0);

        %% Save
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                            'Merged datasets', 'savenew', ...
                            [subid, suffix, 'e_', band, '_prestim_cat.set'], ...
                            'overwrite', 'on', 'gui', 'off');

        %% Save prestim data
        EEG = pop_loadset('filename', [subid, suffix, 'e_', band, '_prestim_cat.set']);

        %% Get metadata
        [n_channels, n_timepoints, n_trials] = size(EEG.data);

        %% Save raw prestim data (channel X time X trials)
        raw_prestim_file = [pwd, '/', subid, suffix, 'e_', band, '_prestim.csv'];

        %% Directory cleanup (if necessary)
        if exist(raw_prestim_file, 'file') == 2
            unix('mkdir -p trash');
            unix(['mv ', raw_prestim_file, ' trash']);
        end

        %% Append channel data to raw power output CSVs
        for c = 1:n_channels
            channel_data = reshape(EEG.data(c,:,:), n_timepoints, n_trials);
            
            % Add column with channel number
            label_c = EEG.chanlocs(c).labels;
            label_c = str2num(label_c(2:end));
            channel_data = [channel_data, repmat(label_c, n_timepoints, 1)];
                                
            dlmwrite(raw_prestim_file, channel_data, '-append');
        end

        %% Pre-Stim ERPs (Parietal Old/New and FN400)
        for i = 1:n_runs
            %% Setup
            r = num2str(runs(i));
    
            %% Load dataset
            EEG = pop_loadset('filename', [subid, '_test', r, suffix, '.set']);

            %% Get Relevant Epochs
            EEG = pop_epoch(EEG, EVENT_TAG, ERP_EPOCH_TIMEBIN, 'newname', ...
                [subid, '_test', num2str(r), '_erp_prestim'], 'epochinfo', 'yes');

            %% Perform baseline correction
            EEG = pop_rmbase(EEG, ERP_BASELINE_TIMEBIN);

            [ALLEEG] = eeg_store(ALLEEG, EEG, i);
        end

        suffix = [suffix, 'e'];

        %% Merge sets
        EEG = pop_mergeset(ALLEEG, 1:n_runs, 0);

        %% Remove bad epochs
        if ~isempty(bad_prestim_epochs)
            EEG = pop_rejepoch(EEG, bad_prestim_epochs, 0);
        end

        %% Save EEGLAB set
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'setname', ...
                            'Merged datasets', 'savenew', ...
                            [subid, suffix, '_erp_prestim_cat.set'], ...
                            'overwrite', 'on', 'gui', 'off');

        %% Save raw
        [n_channels, n_timepoints, n_trials] = size(EEG.data);
    
        erp_prestim_file = [pwd, '/', subid, suffix, '_erp_prestim.csv'];
    
        if exist(erp_prestim_file, 'file') == 2
            unix('mkdir -p trash');
            unix(['mv ', erp_prestim_file, ' trash']);
        end

        for c = 1:n_channels
            channel_data = reshape(EEG.data(c, :, :), n_timepoints, n_trials);
            
            % Add column with channel number
            label_c = EEG.chanlocs(c).labels;
            label_c = str2num(label_c(2:end));
            channel_data = [channel_data, repmat(label_c, n_timepoints, 1)];
                                
            dlmwrite(erp_prestim_file, channel_data, '-append');
        end
    end
end

cd(basedir);

end