function tf_float = Process_NAVIS_float(MBARI_ID_str, dirs, update_str)
% ************************************************************************
% PURPOSE:
%    This function processes raw message files for a given NAVIS float
%    (.msg & .isus), calculates useful values from the raw signals
%    (P, T, S, O2, NO3, pH, CHl, Bbp, CDOM) and then merges these results
%    for a given profile.
%
%    Each profile is saved as a *.mat file with the following

%    format:
%    WMO_ID.PROFILE_#.mat (Ex 5904683.006.mat) in a directory using the
%    WMO_ID for its name. Each file contains 3 structures with variables
%    inside named using ARGO definitions:
%       LR   - Low resolution data
%       HR   - High resolution data
%       INFO - Some information about the profile and float
%
% USAGE:
%	tf_float = Process_NAVIS_float(MBARI_ID_str, dirs, update_str)
%
% INPUTS:
%   MBARI_ID_str  = MBARI Float ID string

%   update_str = "all" or "update"
%                 all    - to process all available msg files
%                 update - only process new msg files

%   dirs       = Either an empty variable or a structure with directory
%                strings where files are located. It must contain these
%                fields at a minimum or be empty. If dirs is empty default
%                paths will be used.
%
%   dirs.msg       = path to float message file directories
%   dirs.mat       = path to *.mat profile files for ARGO NETCDF
%   dirs.cal       = path to *.cal (nitrate) and cal####.mat (working float cal) files
%   dirs.config    = path to config.txt files
%   dirs.temp      = path to temporary working dir
%   dirs.FV        = path to FloatViz files served to web
%   dirs.QCadj     = path to QC adjustment list for all floats
%
% OUTPUTS:
%   tf_float =  1 if processing was a success, 0 otherwise
%
%   Files are saved to WMO dir. This output is intended for input to ARGO
%   NetCDF files via Annie Wong at Univ. of washington and for MBARI use
%   to build ODV compatible *.txt files for FloatViz and SOCCOMViz
%
% HELPER FUNCTIONS CALLED:
%   get_float_cals            get_FloatViz_data       calc_FLOAT_NO3
%   get_MBARI_WMO_list        Calc_SBE63_O2           theta
%   parseNO3cal               betasw_ZHH2009          density
%   get_QC_adjustments        apply_QC_corr
%   get_QCstep_dates          phcalc
%   get_last_cast             parse_NO3msg
%   get_msg_list
%
% CHANGE LOG
% 02/23/17 - If update string  = all, clear all *.mat files in dir 1st.
%       This fixed a potential issue with floats with duplicate UW_ID #'s
% 03/08/17 - Added time delay to file processing. If msg file < 4 hrs old
%       don't process. This prevents a bunch of partial files from being
%       processed (~Line 180)
% 03/28/2017 - added range checks for IB_PH and IK to flag bad pH from bad
%       IB. Added range checks for optode phase and optode T for bad O2
% 04/21/2017 - added code to create PSAL & TEMP QC and ADJUSTED variables.
%       This will be used to get S & T QC flags for the ODV files & pull in
%       ODV flags for S&T.
% 06/27/2017 - added code to each sensor processing section to querry bad
%       sensor list using the function, isbadsensor.m and set quality flags
%       for all profiles on the list to bad
% 06/27/2017 - added code to set unrealistic LR DOXY to "crazy_val"
% 08/01/2017 - fixed code to set QC for O2, NO3 & pH to bad if bad S or T
% 08/11/2017 - add code to catch deployed float with no msg files yet in
%              chemwebdata ~ line 205
% 08/28/17 added code to re-assign dirs.msg directory for special case
%   floats which include duplicate UW ID floats and floats with NO WMO
% 09/29/2017 -  Increased O2 max range from 450 to 550 to cover high O2
%               supersatuaration in artic ice edge blooms
% 10/02/2017 - tweaked code to wait for .isus and .dura files before
% processing.  Added this a couple of weeks ago, but made a minor tweak to
% keep these 'limbo' files included in the email list.
% 12/18/2017 - Added code to include ARGO QC flag == 5 for NPQ corrected data
%   & to process chl for in situ DC (gets added to cal file), NPQ corr.
%   NPQ only gets applied to HR NAVIS data. low res is below 1000m. -jp
% 02/5/2018 - Added code for including "<param>_DATA_MODE" variables in Argo mat files
%	This is used in identifying whether a cycle is real-time or delayed mode, for BRtransfer purposes.
% 05/25/18 Add code so that CHL_ADJUSTED is always calculated if the raw
%           data exists. If an in situ DC can't be determined the factory
%           DC is used. - jp
% 05/31/2018 Added spiketest for DOXY, NITRATE, PH_IN_SITU_TOTAL (raw and adjusted)
% 08/14/2018 Added secial case for 0948 and 0949 processing (Fassbender
%       EXPORTS floats).  These have not pH temp, and also different FLBB
%       column headers.  However, moving forward all NAVIS will not have pH
%       temp, so need a more permanent solution.
% 08/23/2018  Added special case for 0948 and 0949 N processing (Fassbender
%       EXPORTS floats).  These have a spike in nitrate toward surface due to
%       high NO3 gradient and the lag in sample timing btwn SUNA and CTD.
%
% 09/10/18 Added code to process floats with seconday pH pressure coefficients.
%     At this point this change onlly afects 0690. -jp
% 09/11/2018, TM changed calls to isbadsensor.m in support of adding QF='questionable' to bad sensor list capabilities.
% 01/07/2019, JP Added code to choose CDT T for pH if pH T doesn't exist.
%   Updated QC flagging process to add flags for PH_TEMP_QC & use working
%   temp to flag pH QC
% 01/16/19, TM, replaced phcalc_jp.m with phcalc.m
% 10/27/20, TM/JP Modification for compatability with NAVIS new msg file
%    format (with pH diag); TM, minor mods to accomadate change to parser (inclusion of sdn in gps vector).
% 03/11/2021 JP, modified for GOBGC file name change and updates to some
% other functions. Still could use a thourough clean up when time permits
% 4/29/21 TM modified the call to getTRUE_SUNAtemp -- this used to be an exception for the 2 OSP Fassbender floats; now applying to all SUNAs.
% 6/2/21 TM format to Calc_SBE63_O2 changed in support of new SBE83 in-air
%        optode (first deployed on APEX float, but calls to this routine also in
%        Process_NAVIS_float).
% 6/22/21 TM, Added code to transfer BBP700 to BBP700_ADJUSTED in real time
%       (same for BBP532).  Also included are slight modifications to the
%       specification of DOXY SCIENTIFIC_CALIB fields.
% ************************************************************************

% FOR TESTING
%MBARI_ID_str = 'un0037';
% MBARI_ID_str = 'un0565';
% update_str   = 'all';
% dirs =[];

% ************************************************************************
% SET FORMATS, DEFAULT DIRS, PREDIMENSION STRUCTURE, BOOKKEEPING
% ************************************************************************
fclose all; % CLOSE ANY OPEN FILES
tf_float.status = 0; % Flag for float processing success 0 = no good
tf_float.new_messages = {};
tf_float.bad_messages = {};

% THIS IS A LIST OF FLOATS WITH BAD NO3 FROM THE START OR NO3 LISTED IN THE
% MSG HEADER BUT NO SENSOR ON BOARD
bad_no3_filter = 'un0691|un0569|ua7622|ua18340|un0887';

% THIS IS A LIST OF FLOATS WITH WITH STRONG O2 GRADIENTS AT THE SURFACE
% NO SPIKE TESTS PERFORMED ON THESE FLOATS (CURRENTLY JUST ARCTIC FLOATS)
no_o2_spike = 'un0691|ua7564|';

% CDOM channel really a second BBP channel(532
cdom_bbp532_chk = 'un0565';

% ************************************************************************
% **** DEFAULT STRUCTURE FOR DIRECTORY PATHS ****
if isempty(dirs)
    user_dir = getenv('USERPROFILE'); %returns user path,i.e. 'C:\Users\jplant'
    %user_dir = [user_dir, '\Documents\MATLAB\ARGO_PROCESSING\DATA\'];
    user_dir = [user_dir, '\Documents\MATLAB\ARGO_PROCESSING\DATA\'];
    
    dirs.mat       = [user_dir,'FLOATS\'];
    dirs.cal       = [user_dir,'CAL\'];
    dirs.FV        = [user_dir,'FLOATVIZ\'];
    
    dirs.QCadj     = [user_dir,'CAL\QC_LISTS\'];
    dirs.temp      = 'C:\temp\';
    dirs.msg       = '\\seaecho.shore.mbari.org\floats\';
    
    dirs.log = [user_dir,'Processing_logs\'];
    
    bad_sensor_list = parse_bad_sensor_list([dirs.cal,'bad_sensor_list.txt']);
    iM   = find(strcmp('MBARI ID STR',bad_sensor_list.hdr) == 1);
    % CHECK IF SPECIFC FLOAT HAS BAD SENSOR ISSUES
    if ~isempty(bad_sensor_list.list)
        tSENSOR = strcmp(MBARI_ID_str,bad_sensor_list.list(:,iM));
        if sum(tSENSOR) > 0
            disp([MBARI_ID_str,' found on the bad sensor list!'])
            BSL = bad_sensor_list;
            BSL.list = BSL.list(tSENSOR,:);
            dirs.BSL = BSL;
            clear BSL
        else
            dirs.BSL.hdr  = [];
            dirs.BSL.list = [];
        end
        clear tSENSOR
    end
    
elseif ~isstruct(dirs)
    disp('Check "dirs" input. Must be an empty variable or a structure')
    return
end

% ************************************************************************

% SET DATA FILL VALUES
fv.bio = 99999;
fv.QC  = 99;

% VALID BIO ARGO RANGE CHECKS - RAW DATA [MIN MAX]
RCR.P     = [0 12000];
RCR.S     = [26 38]; % from argo parameter list
RCR.T     = [-2.5 40]; % from argo parameter list
RCR.O     = [-5 550]; % from argo parameter list
RCR.OP    = [10 70]; % optode phase, from argo parameter list
RCR.OT    = [-2.5 40]; % optode temperature, from argo parameter list
RCR.CHL   = [-0.1 150]; % argoBGC QC manual 09July2016
RCR.BB700 = [-0.000025 0.1]; % argoBGC QC manual 09July2016
RCR.BB532 = [-0.000005 0.1]; % argoBGC QC manual 09July2016
RCR.CDOM = [-1000 1000]; % Place Holder
RCR.NO3  = [-15 65];
RCR.PH   = [7.0 8.8];
RCR.PHT  = [-2.5 40];
RCR.PHV  = [-1.2 -0.7]; % Range check on pH volts
RCR.IB   = [-100 100]; % Range check on pH Ib, nano amps
RCR.IK   = [-100 100]; % Range check on pH Ik, nano amps

% VALID BIO ARGO RANGE CHECKS - QC DATA [MIN MAX]
RC.P     = [0 12000];
RC.S     = [26 38]; % from argo parameter list
RC.T     = [-2.5 40]; % from argo parameter list
RC.O     = [-5 550]; % from argo parameter list
RC.OP    = [10 70]; % optode phase, from argo parameter list
RC.OT    = [-2.5 40]; % optode temperature, from argo parameter list
RC.CHL   = [-0.1 50]; % argoBGC QC manual 09July2016
RC.BB700 = [-0.000025 0.1]; % argoBGC QC manual 09July2016
RC.BB532 = [-0.000005 0.1]; % argoBGC QC manual 09July2016
RC.CDOM  = [-1000 1000]; % Place Holder
RC.NO3   = [-10 55];
RC.PH    = [7.3 8.5];
RC.PHV   = [-1.2 -0.7]; % Range check on pH volts
RC.IB    = [-100 100]; % Range check on pH Ib, nano amps
RC.IK    = [-100 100]; % Range check on pH Ik, nano amps

UW_ID_str = regexp(MBARI_ID_str,'^\d+', 'once','match');
crazy_val = 99990;

% ************************************************************************
% LOAD OR BUILD CALIBRATION DATA
% ************************************************************************
fp_cal = [dirs.cal,'cal',MBARI_ID_str,'.mat'];
if exist(fp_cal,'file') == 2
    load(fp_cal);
    disp(' ')
    disp(['FLOAT ',MBARI_ID_str, '(',cal.info.WMO_ID,')']);
    disp(['Existing calibration file loaded: ',fp_cal])
    
    % temporary WMO still - try and update
    if strncmp(cal.info.WMO_ID,'NO', 2) && cal.info.tf_bfile ~= 0
        disp(['Attempting to retrieve updated WMO num by deleting ', ...
            'and rebuilding cal file ',fp_cal])
        delete(fp_cal)
        cal = get_float_cals(MBARI_ID_str, dirs); %WMO found
        if regexp(cal.info.WMO_ID, '^\d{7}', 'once')
            update_str = 'all';
        end
    end
else % No cal file built so build it
    fprintf('\n\n');
    disp(['FLOAT ',MBARI_ID_str]);
    cal = get_float_cals(MBARI_ID_str, dirs);
end

if isempty(cal)
    disp(['NO CALIBRATION DATA FOR ',MBARI_ID_str])
    return
end

% CHECK FOR FLOAT TYPE IF NOT APEX NAVIS
float_type = cal.info.float_type;
if strcmp(float_type,'NAVIS') % NAVIS
    disp([cal.info.name,' is an NAVIS float'])
elseif strcmp(float_type,'APEX') % APEX
    disp(['Float ',cal.info.name, ' appears to be an APEX float.'])
    disp(['Processing should be done with Process_APEX_float.m',...
        ' instead'])
    return
elseif strcmp(float_type,'SOLO') % SOLO
    disp(['Float ',cal.info.name, ' appears to be a SOLO float.'])
    disp(['Processing should be done with Process_SOLO_float.m',...
        ' instead'])
    return
else
    disp('Unknown float type')
    return
end

% CHECK FOR WL_OFFSET IN ISUS NITRATE CAL
% IF IT EXISTS AND IS NOT THE DEFAULT (210), COMMENT
if isfield(cal, 'N')
    if isfield(cal.N, 'WL_offset') && cal.N.WL_offset ~= 210
        disp(['NON STANDARD WAVE LENGTH OFFSET IN NITRATE CAL = ',...
            num2str(cal.N.WL_offset)]);
    end
end
clear dirs.config dirs.cal s1

% ************************************************************************
% GET QC ADJUSTMENT DATA
% ************************************************************************
QC = get_QC_adjustments(cal.info.WMO_ID, dirs);

% ************************************************************************
% GET MSG AND ISUS FILE LISTS
% call returns a structure of hdr & list{file name, file dir, & file date}
mlist = get_msg_list(cal.info, 'msg');
ilist = get_msg_list(cal.info, 'isus');

% CHECK FOR EMTPY MSG DIR - if msgdir is empty - FLOAT HAS NOT SENT
% ANY MSG FILES YET
if isempty(mlist.list)
    disp([MBARI_ID_str, ' may be deployed but it has not sent any *.msg',...
        ' files yet!']);
    return
end

% GIVE FILE PROCESSING A TIME LAG - ONLY PROCESS FILES > 4 HRS
% SEEMS LIKE SEVERAL INTERATIONS OF INCOMPLETE FILES CAN BE TRANSMITTED
% DURING SURFACING

% TEST FOR FILE AGE LESS THEN 4 HOURS OLD
% REMOVE THESE FILES FROM LIST
age_limit = now - 4/24;
%age_limit = now; % no lag if you want an imediate process

if ~isempty(mlist.list)
    t1 = cell2mat(mlist.list(:,3)) < age_limit;
    mlist.list = mlist.list(t1,:);
end

if ~isempty(ilist.list)
    t1 = cell2mat(ilist.list(:,3)) < age_limit;
    ilist.list = ilist.list(t1,:);
end

clear t1

% ************************************************************************
% LOOK FOR MOST RECENT PROFILE FILE (*.mat) AND ANY MISSING CASTS
% ONLY WANT NEW OR MISSING CASTS IN THE COPY LIST
% YOU MUST DELETE A MAT FILE TO REDO IF IT IS PARTIAL FOR A GIVEN CAST
% ************************************************************************
[last_cast, missing_casts, first_sdn] = get_last_cast(dirs.mat, ...
    cal.info.WMO_ID);
if isempty(last_cast)
    last_cast = 0; % set low for logic tests later
end

% UPDATE MODE -- ONLY LOOK FOR NEW FILES
if strcmp(update_str, 'update') && last_cast > 0
    if ~isempty(mlist.list)
        tmp   = (regexp(mlist.list(:,1),'(?<=\d+\.)\d{3}(?=\.msg)','match','once'));
        casts = str2double(tmp);
        t1    = casts > last_cast; % new cycles in file list
        t2    = ismember(casts, missing_casts); %loc of missing in file list
        mlist.list = mlist.list(t1|t2,:);
    end
    
    if ~isempty(ilist.list)
        tmp   = (regexp(ilist.list(:,1),'(?<=\d+\.)\d{3}(?=\.isus)','match','once'));
        casts = str2double(tmp);
        t1    = casts > last_cast; % new cycles in file list
        t2    = ismember(casts, missing_casts); %loc of missing in file list
        ilist.list = ilist.list(t1|t2,:);
    end
end
clear tmp t1 t2 casts

% ************************************************************************
% COPY FLOAT MESSAGE FILES TO LOCAL TEMPORARY DIRECTORY
% Three file groups *.msg, *.isus, *.dura
% ************************************************************************
if isempty(mlist.list)
    disp(['No float message files found to process for float ',MBARI_ID_str]);
    disp(['Last processed cast: ',sprintf('%03.0f',last_cast)])
    return
end

disp(['Copying message files to ', dirs.temp, '  .......'])

% COPY *.MSG files
if ~isempty(ls([dirs.temp,'*.msg']))
    delete([dirs.temp,'*.msg']) % Clear any message files in temp dir
end
if ~isempty(mlist.list)
    for i = 1:size(mlist.list,1)
        fp = fullfile(mlist.list{i,2}, mlist.list{i,1});
        copyfile(fp, dirs.temp);
    end
end

% COPY *.ISUS files
if ~isempty(ls([dirs.temp,'*.isus']))
    delete([dirs.temp,'*.isus']) % Clear any message files in temp dir
end
if ~isempty(ilist.list)
    for i = 1:size(ilist.list,1)
        fp = fullfile(ilist.list{i,2}, ilist.list{i,1});
        copyfile(fp, dirs.temp);
    end
end

% ************************************************************************
% CHECK FOR WMO ID & DIR, IF NO WMO ASSIGNED YET NOTIFY
% IF WMO DIR NOT THERE MAKE IT,
% IF UPDATE = ALL, CLEAR FILES
% ************************************************************************
% CHECK FOR WMO ID
WMO  = cal.info.WMO_ID;

if strncmp(WMO,'^NO_WMO',6) && cal.info.tf_bfile == 0
    fprintf('WMO will never be assigned to %s\n', cal.info.name);
elseif strncmp(WMO,'^NO_WMO',6)
    fprintf('No WMO number assigned to %s yet\n', cal.info.name);
end

% CHECK FOR EXISTING WMO DIR, CREATE IF NOT THERE
if exist([dirs.mat,WMO,'\'],'dir') ~= 7
    status = mkdir([dirs.mat,WMO,'\']);
    if status == 0
        disp(['Directory could not be created at: ', ...
            [dirs.mat,WMO,'\']]);
        tf_float.status = 0;
        return
    end
end

% IF UPDATE STR = ALL, CLEAR MAT FILES IN WMO DIR
if strcmp(update_str,'all')
    file_chk = ls([dirs.mat,WMO,'\*.mat']);
    if ~isempty(file_chk)
        disp(['Updating all files, clearing existing *.mat files from ',...
            dirs.mat,WMO,'\ first!'])
        delete([dirs.mat,WMO,'\*.mat']);
    end
end

% ***********************************************************************
% GET DIR LIST AS STRUCTURE - THIS WILL BE USED TO SEND AN EMAIL OF
% ARRIVING NEW MSG FILES
mdir = dir([dirs.temp,'*.msg']);
[rr,~] = size(mdir);
if rr > 0
    new_msgs = cell(rr,1);
    ct = 0;
    for m_ct = 1:rr
        tmp_cycle = str2double(regexp(mdir(m_ct).name,'\d+(?=\.msg)', ...
            'once','match')); % profile # from name
        %TM 3/2/21.  Why did we exclude the missing casts from the
        %final reporting?  This is useful info for floats in
        %catchup mode.  Not sure what the original reasoning was?
        %Perhaps I'm missing something.  I think we want to modify
        %this moving forward, but maybe still distinguish between
        %the two (["new"] VS ["previously missing" or "catch-up"]).
        t1 = missing_casts == tmp_cycle;% missing or new? only add new
        if sum(t1) == 0
            ct = ct+1;
            str = sprintf('%s\t%s\t%s\t%s\t%0.1f','new     :', WMO,mdir(m_ct).name, ...
                datestr(mdir(m_ct).datenum,'mm/dd/yy HH:MM'), ...
                mdir(m_ct).bytes/1000);
            new_msgs{ct} = str;
            tf_float.status = 1;
        else
            ct = ct+1;
            str = sprintf('%s\t%s\t%s\t%s\t%0.1f','catch-up:', WMO,mdir(m_ct).name, ...
                datestr(mdir(m_ct).datenum,'mm/dd/yy HH:MM'), ...
                mdir(m_ct).bytes/1000);
            new_msgs{ct} = str;
            tf_float.status = 1;
        end
    end
    tf_float.new_messages = new_msgs(1:ct); % list of new msgs from float
    %clear mdir rr new_msgs str
end

% ***********************************************************************

msg_list   = ls([dirs.temp,'*.msg']); % get list of file names to process
lr_ind_chk = 0; % indice toggle - find indices once per float

% GET BAD SENSOR LIST FOR FLOAT IF ANY
BSL = dirs.BSL;

for msg_ct = 1:size(msg_list,1)
    clear LR HR INFO
    msg_file = strtrim(msg_list(msg_ct,:));
    NO3_file = regexprep(msg_file,'msg','isus');
    % find block of numbers then look ahead to see if '.msg' follows
    cast_num = regexp(msg_file,'\d+(?=\.msg)','once','match');
    
    %disp(['Processing float ' cal.info.name, ' profile ',cast_num])
    d = parse_NAVISmsg4ARGO([dirs.temp,msg_file]);
    if ~isempty(d.lr_hdr)
        if strcmp(d.lr_hdr{7},'Mch1') %Quick hack to get around different column headers in msg file for flbb!!
            d.lr_hdr{7} = 'Fl'; %'Mch1'
            d.lr_hdr{8} = 'Bb'; %'Mch2'
            d.lr_hdr{9} = 'Cdm'; %'Mch3'
            d.hr_hdr{6} = 'Fl'; %'Mch1'
            d.hr_hdr{7} = 'Bb'; %'Mch2'
            d.hr_hdr{8} = 'Cdm'; %'Mch3'
        end
    end
    
    
    %     % IF MSG FILE EXIST BUT NO LR DATA REMOVE FROM NEW LIST AND
    %     % PUT IN BAD LIST
    %     if isempty(d.lr_d)
    %         %         msg_size = size(msg_file,2);
    %         %         if sum(t1>0)
    %         %         t1 = strncmp(tf_float.new_messages, msg_file, msg_size);
    %         Indext1 = strfind(tf_float.new_messages,msg_file);
    %         t1 = find(not(cellfun('isempty',Indext1)));
    %         if ~isempty(t1)
    %             tf_float.bad_messages = [tf_float.bad_messages; ...
    %                 tf_float.new_messages(t1)];
    %             tf_float.new_messages(t1) =[];
    %         end
    %     end
    
    % IF MSG FILE EXIST BUT NO LR DATA REMOVE FROM NEW LIST AND
    % PUT IN BAD LIST
    if isempty(d.lr_d)
        t1 = ~cellfun(@isempty,regexp(tf_float.new_messages, msg_file,'once'));
        tf_float.bad_messages = [tf_float.bad_messages; ...
            tf_float.new_messages(t1)];
        tf_float.new_messages(t1) =[];
        if isempty(tf_float.new_messages)
            tf_float.status = 0; % NO VALID MESSAGES LEFT TO PROCESS
            disp(['No complete float message files found to process', ...
                'for float ',MBARI_ID_str]);
            disp(['Last processed cast: ',sprintf('%03.0f',last_cast)])
            return
        end
    end
    
    fileinfos = dir([dirs.temp,msg_file]);
    timestamps = fileinfos.date;
    timediff = now-datenum(timestamps); % was using 'd.sdn', but for floats just coming up from under ice that doesn't make sense.
    %make sure all files are present if float includes all sensors,
    %otherwise, end processing for this cycle (but if msg file is > 20 days old, and still no isus, then process as usual)
    if regexp(MBARI_ID_str, bad_no3_filter, 'once') % EXCEPTIONS
        disp([MBARI_ID_str,' Nitrate sensor failed from the start & ', ...
            'never any isus files to  process'])
    else
        if (exist([dirs.temp, NO3_file],'file')==0 && isfield(cal,'N') && timediff<=20)
            disp('*******************************************************')
            disp(['WARNING: .isus FILE IS MISSING FOR: ',msg_file])
            disp(['PROCESSING HALTED FOR ',msg_file,' UNTIL ALL FILES ARE PRESENT.'])
            disp('*******************************************************')
            %             msg_size = size(msg_file,2);
            %             t1 = strncmp(tf_float.new_messages, msg_file, msg_size);
            %             if sum(t1>0)
            Indext1 = strfind(tf_float.new_messages,msg_file);
            t1 = find(not(cellfun('isempty',Indext1)));
            if ~isempty(t1)
                tf_float.new_messages(t1) ={[char(tf_float.new_messages(t1)), ...
                    ' .isus lag']}; %mark on list as in limbo
            end
            continue
        end
    end
    
    % GATHER INFO FOR BUILDING ODV FILE LATER AND JUST TO MAKE LIFE
    % EASIER
    INFO.CpActivationP = d.CpActivationP;
    INFO.FwRev    = d.FwRev;
    INFO.CTDtype  = d.CTDtype;
    INFO.CTDsn    = d.CTDsn;
    INFO.FlbbMode = d.FlbbMode;
    if INFO.FlbbMode == 1
        master_FLBB = 1;
    end
    
    INFO.sdn      = d.sdn;
    INFO.cast     = d.cast;
    INFO.gps      = d.gps;
    
    INFO.INST_ID  = cal.info.INST_ID;
    INFO.name   = cal.info.name;
    INFO.WMO_ID = cal.info.WMO_ID;
    INFO.float_type = float_type;
    
    INFO.EOT    = d.EOT;
    
    
    % ********************************************************************
    % SOME DATA FINESSING
    % NEED TO SAMPLE HIGH RES DATA TO FILL IN LOW RES DATA
    % NITRATE NOT SAMPLED IN CP MODE
    % ********************************************************************
    if isempty(d.lr_d) % CHECK FOR DATA
        disp(['No low res data in message file for ', ...
            strtrim(msg_list(msg_ct,:))])
        continue
    else % if data also header variable
        % Low resolution data
        lr_rows = size(d.lr_d,1);
        IX      = (lr_rows: -1 : 1)'; % build reverse indices - ARGO WANTS SHALLOW TO DEEP
        lr_d    = d.lr_d(IX,:); % ARGO WANTS SHALLOW TO DEEP
        clear B IX lr_rows
    end
    
    hr_d  = d.hr_d; % HR DATA, BUT COULD BE EMPTY
    [r_lr, c_lr] = size(lr_d);   % low res data dimmensions
    [r_hr, c_hr] = size(hr_d); % high res data dimmensions
    
    % if nitrate add col to high res data
    if r_hr > 0 && sum(strcmp('no3', d.lr_hdr)) == 1
        hr_d = [hr_d(:,1:3), hr_d(:,1)*NaN, hr_d(:,4:c_hr)];
    end
    % ****************************************************************
    % DO SOME ONE TIME TASKS
    % ****************************************************************
    % GET VARIABLE INDICES - ONLY NEED TO DO THIS ONCE PER FLOAT
    if lr_ind_chk == 0
        lr_ind_chk = 1;
        
        iP     = find(strcmp('p',   d.lr_hdr) == 1); % CTD P
        iT     = find(strcmp('t',   d.lr_hdr) == 1); % CTD T
        iS     = find(strcmp('s',   d.lr_hdr) == 1); % CTD S
        iNO3   = find(strcmp('no3', d.lr_hdr) == 1); % Nitrate
        iPhase = find(strcmp('O2ph',d.lr_hdr) == 1); % Phase SBE63
        iTo    = find(strcmp('O2tV',d.lr_hdr) == 1); % optode temp
        iChl   = find(strcmp('Fl',  d.lr_hdr) == 1); % CHL fluor
        iBb    = find(strcmp('Bb',  d.lr_hdr) == 1); % Backscatter
        iCdm   = find(strcmp('Cdm', d.lr_hdr) == 1); % CDOM, NAVIS
        if isempty(iCdm)
            iCdm   = find(strcmp('Cd', d.lr_hdr) == 1); % NAVIS 0037,0276
        end
        iphV   = find(strcmp('phV', d.lr_hdr) == 1); % pH volts
        if isempty(iphV)
            iphV   = find(strcmp('phVrs', d.lr_hdr) == 1); % pH volts
        end
        iphT   = find(strcmp('phT', d.lr_hdr) == 1); % pH Temp
        
        iNB_CTD   = find(strcmp('nbin ctd',    d.hr_hdr) == 1); % CTD P
        iNB_DOXY  = find(strcmp('nbin oxygen', d.hr_hdr) == 1); % CTD P
        iNB_MCOM  = find(strcmp('nbin MCOMS',  d.hr_hdr) == 1); % CTD P
        iNB_PH    = find(strcmp('nbin pH',     d.hr_hdr) == 1); % CTD P
        
        % GET FLOATVIZ DATA - REG AND QC
        % WILL BE USED TO EXTRACT QF DATA FLAGS LATER
        FVQC_flag = 1;
        %         mymockSirocco = 'C:\Users\bgcargo\Documents\MATLAB\ARGO_PROCESSING_siroccoMock\DATA\FLOATVIZ\';
        %         FV_data     = get_FloatViz_data([mymockSirocco,INFO.WMO_ID,'.TXT']);
        %         FV_QCdata   = get_FloatViz_data([mymockSirocco,'QC\',INFO.WMO_ID,'QC.TXT']);
        FV_data   = get_FloatViz_data(INFO.WMO_ID);
        FV_QCdata = get_FloatViz_data([INFO.WMO_ID,'QC']);
        if isempty(FV_QCdata)
            FV_QCdata = FV_data;
            FVQC_flag = 0;
        end
        
    end
    
    % ****************************************************************
    % ASSIGN DATA TO ARGO VARIABLES
    % ****************************************************************
    fill0     = ones(r_lr,1)* 0; % ZERO ARRAY, AN ARRAY FILLER
    fill0_hr  = ones(r_hr,1)* 0; % ZERO ARRAY, AN ARRAY FILLER
    
    lr_potT   = theta(lr_d(:,iP), lr_d(:,iT), lr_d(:,iS),0);
    lr_den    = density(lr_d(:,iS), lr_potT); % kg/ m^3, pot den
    if r_hr > 0
        hr_potT   = theta(hr_d(:,iP), hr_d(:,iT), hr_d(:,iS),0);
        hr_den    = density(hr_d(:,iS), hr_potT); % kg/ m^3, pot den
    end
    
    % P, T, S
    LR.PRES  = lr_d(:,iP);
    LR.PRES_QC          = fill0 + fv.QC;
    LR.PRES_ADJUSTED    = LR.PRES;
    LR.PRES_ADJUSTED_QC = fill0 + fv.QC;
    
    LR.PSAL             = lr_d(:,iS);
    LR.PSAL_QC          = fill0 + fv.QC;
    LR.PSAL_ADJUSTED    = LR.PSAL;
    LR.PSAL_ADJUSTED_QC = fill0 + fv.QC;
    
    LR.TEMP             = lr_d(:,iT);
    LR.TEMP_QC          = fill0 + fv.QC;
    LR.TEMP_ADJUSTED    = LR.TEMP;
    LR.TEMP_ADJUSTED_QC = fill0 + fv.QC;
    
    % CHECK FOR BAD PRESS VALUES
    LRQF_P = LR.PRES < RCR.P(1) | LR.PRES > RCR.P(2);
    LR.PRES_QC(LRQF_P)  = 4;  % BAD
    LR.PRES_QC(~LRQF_P & LR.PRES ~= fv.bio) = 1; % GOOD
    
    LR.PRES_ADJUSTED_QC(LRQF_P)  = 4;  % BAD
    LR.PRES_ADJUSTED_QC(~LRQF_P & LR.PRES_ADJUSTED ~= fv.bio) = 1; % GOOD
    % ADD SALINITY & TEMP QF BECAUSE BAD S PERCOLATES TO
    % O, N and pH, density
    [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'S');
    LRQF_S   = LR.PSAL < RCR.S(1) | LR.PSAL > RCR.S(2);
    t_bio  = LR.PSAL ~= fv.bio;
    
    LR.PSAL_QC(LRQF_S)  = 4;  % BAD
    LR.PSAL_QC(~LRQF_S & LR.PSAL ~= fv.bio) = 1; % GOOD
    LR.PSAL_QC(t_bio) = LR.PSAL_QC(t_bio) * ~BSLflag + BSLflag*theflag;
    LR.PSAL_ADJUSTED_QC(LRQF_S)  = 4;  % BAD
    LR.PSAL_ADJUSTED_QC(~LRQF_S & LR.PSAL_ADJUSTED ~= fv.bio) = 1;
    LR.PSAL_ADJUSTED_QC(t_bio) = LR.PSAL_ADJUSTED_QC(t_bio) * ...
        ~BSLflag + BSLflag*theflag;% GOOD
    
    
    [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'T');
    LRQF_T  = LR.TEMP < RCR.T(1) | LR.TEMP > RCR.T(2);
    t_bio   = LR.TEMP ~= fv.bio;
    
    LR.TEMP_QC(LRQF_T)  = 4;  % BAD
    LR.TEMP_QC(~LRQF_T & LR.TEMP ~= fv.bio) = 1; % GOOD
    LR.TEMP_QC(t_bio) = LR.TEMP_QC(t_bio) * ~BSLflag + BSLflag*theflag;
    LR.TEMP_ADJUSTED_QC(LRQF_T)  = 4;  % BAD
    LR.TEMP_ADJUSTED_QC(~LRQF_T & LR.TEMP_ADJUSTED ~= fv.bio) = 1; % GOOD
    LR.TEMP_ADJUSTED_QC(t_bio) = LR.TEMP_ADJUSTED_QC(t_bio) * ...
        ~BSLflag + BSLflag*theflag;
    
    % HIGH RES DATA
    if r_hr > 0
        HR.PRES = hr_d(:,iP);
        HR.PRES_ADJUSTED = HR.PRES;
        
        HR.PSAL = hr_d(:,iS);
        HR.PSAL_ADJUSTED = HR.PSAL;
        HR.TEMP = hr_d(:,iT);
        HR.TEMP_ADJUSTED = HR.TEMP;
        
        
        HR.PRES_QC = fill0_hr + fv.QC; % Predimmension QF's
        HR.PRES_ADJUSTED_QC = HR.PRES_QC;
        HR.PSAL_QC = fill0_hr + fv.QC; % Predimmension QF's
        HR.PSAL_ADJUSTED_QC = HR.PSAL_QC;
        HR.TEMP_QC = HR.PSAL_QC;
        HR.TEMP_ADJUSTED_QC = HR.PSAL_QC;
        
        % CHECK FOR BAD PRESS VALUES
        HRQF_P = HR.PRES < RCR.P(1) | HR.PRES > RCR.P(2);
        HR.PRES_QC(HRQF_P)  = 4;  % BAD
        HR.PRES_QC(~HRQF_P & HR.PRES ~= fv.bio) = 1; % GOOD
        
        HR.PRES_ADJUSTED_QC(HRQF_P)  = 4;  % BAD
        HR.PRES_ADJUSTED_QC(~HRQF_P & HR.PRES_ADJUSTED ~= fv.bio) = 1; % GOOD
        
        
        
        [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'S');
        HRQF_S  = HR.PSAL < RCR.S(1) | HR.PSAL > RCR.S(2);
        t_bio   = HR.PSAL ~= fv.bio;
        
        HR.PSAL_QC(HRQF_S) = 4;  % BAD
        HR.PSAL_QC(~HRQF_S & HR.PSAL ~= fv.bio) = 1; % GOOD
        HR.PSAL_QC(t_bio) = HR.PSAL_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        HR.PSAL_ADJUSTED_QC(HRQF_S)  = 4;  % BAD
        HR.PSAL_ADJUSTED_QC(~HRQF_S & HR.PSAL_ADJUSTED ~= fv.bio) = 1; % GOOD
        HR.PSAL_ADJUSTED_QC(t_bio) = HR.PSAL_ADJUSTED_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        
        [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'T');
        HRQF_T   = HR.TEMP < RCR.T(1) | HR.TEMP > RCR.T(2);
        t_bio   = HR.TEMP ~= fv.bio;
        
        HR.TEMP_QC(HRQF_T)  = 4;  % BAD
        HR.TEMP_QC(~HRQF_T & HR.TEMP ~= fv.bio) = 1; % GOOD
        HR.TEMP_QC(t_bio) = HR.TEMP_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        HR.TEMP_ADJUSTED_QC(HRQF_T)  = 4;  % BAD
        HR.TEMP_ADJUSTED_QC(~HRQF_T & HR.TEMP_ADJUSTED ~= fv.bio) = 1; % GOOD
        HR.TEMP_ADJUSTED_QC(t_bio) = HR.TEMP_ADJUSTED_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        
        if isempty(iNO3) % nitrate exists need to add +1 to bin index)
            index_add = 0;
        else
            index_add = 1;
        end
        
        HR.NBIN_CTD   = hr_d(:,iNB_CTD + index_add);
        HR.NBIN_DOXY  = hr_d(:,iNB_DOXY + index_add);
        HR.NBIN_MCOMS = hr_d(:,iNB_MCOM) + index_add;
        if ~isempty(iNB_PH)
            HR.NBIN_PH = hr_d(:,iNB_PH + index_add);
        end
        
    else
        HR.PRES = [];
        HR.PRES_ADJUSTED = [];
        HR.PSAL = [];
        HR.PSAL_ADJUSTED = [];
        HR.TEMP = [];
        HR.TEMP_ADJUSTED = [];
        HR.NBIN_CTD   = [];
        HR.NBIN_DOXY  = [];
        HR.NBIN_MCOMS = [];
        if ~isempty(iNB_PH)
            HR.NBIN_PH = [];
        end
    end
    
    % ****************************************************************
    % CALCULATE OXYGEN CONCENTRATION
    % ****************************************************************
    if ~isempty(iPhase) % LR O2 data should exist
        
        LR.PHASE_DELAY_DOXY     = fill0 + fv.bio; % predim
        LR.PHASE_DELAY_DOXY_QC  = fill0 + fv.QC;
        LR.TEMP_VOLTAGE_DOXY    = fill0 + fv.bio;
        LR.TEMP_VOLTAGE_DOXY_QC = fill0 + fv.QC;
        LR.DOXY                 = fill0 + fv.bio;
        LR.DOXY_QC              = fill0 + fv.QC;
        LR.TEMP_DOXY            = fill0 + fv.bio;
        LR.TEMP_DOXY_QC         = fill0 + fv.QC;
        LR.DOXY_ADJUSTED        = fill0 + fv.bio;
        LR.DOXY_ADJUSTED_QC     = fill0 + fv.QC;
        LR.DOXY_ADJUSTED_ERROR  = fill0 + fv.bio;
        INFO.DOXY_SCI_CAL_EQU   = 'not applicable';
        INFO.DOXY_SCI_CAL_COEF  = 'not applicable';
        INFO.DOXY_SCI_CAL_COM   = 'not applicable';
        INFO.DOXY_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR.PHASE_DELAY_DOXY     = fill0_hr + fv.bio; % predim
        HR.PHASE_DELAY_DOXY_QC  = fill0_hr + fv.QC;
        HR.TEMP_VOLTAGE_DOXY    = fill0_hr + fv.bio;
        HR.TEMP_VOLTAGE_DOXY_QC = fill0_hr + fv.QC;
        HR.DOXY                 = fill0_hr + fv.bio;
        HR.DOXY_QC              = fill0_hr + fv.QC;
        HR.TEMP_DOXY            = fill0_hr + fv.bio;
        HR.TEMP_DOXY_QC         = fill0_hr + fv.QC;
        HR.DOXY_ADJUSTED        = fill0_hr + fv.bio;
        HR.DOXY_ADJUSTED_QC     = fill0_hr + fv.QC;
        HR.DOXY_ADJUSTED_ERROR  = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iPhase)); % missing data?
        lr_O2_matrix           = lr_d(:,[iP,iT,iS,iPhase,iTo]); % LR & HR
        [ppoxdoxy, lr_O2_umolL, lr_O2_T] = Calc_SBE63_O2(lr_O2_matrix, cal.O);
        lr_O2_umolkg           = lr_O2_umolL ./ lr_den *1000;
        
        LR.PHASE_DELAY_DOXY(~lr_nan)     = lr_d(~lr_nan, iPhase); % predim
        LR.PHASE_DELAY_DOXY_QC(~lr_nan)  = fv.QC;
        LR.TEMP_VOLTAGE_DOXY(~lr_nan)    = lr_d(~lr_nan, iTo);
        LR.TEMP_VOLTAGE_DOXY_QC(~lr_nan) = 3;
        LR.DOXY(~lr_nan)                 = lr_O2_umolkg(~lr_nan);
        tlrDOXY = abs(LR.DOXY) > crazy_val & ~lr_nan; % Unrealistic bad value
        LR.DOXY(tlrDOXY) = crazy_val; % SET TO crazy bad value
        LR.DOXY_QC(~lr_nan)              = 3;
        %LR.DOXY_QC(tlrDOXY) = 4;
        LR.DOXY_QC(LRQF_S | LRQF_T)      = 4; % VERY BAD S or T
        LR.TEMP_DOXY(~lr_nan)            = lr_O2_T(~lr_nan);
        LR.TEMP_DOXY_QC(~lr_nan)         = 3;
        clear lr_O2_matrix lr_O2_umolL lr_O2_T lr_O2_umolkg
        
        
        
        if r_hr > 0 % HR DATA SHOULD EXIST TOO
            hr_nan = isnan(hr_d(:,iPhase)); % missing data?
            hr_O2_matrix           = hr_d(:,[iP,iT,iS,iPhase,iTo]); % HR
            [ppoxdoxy, hr_O2_umolL, hr_O2_T] = Calc_SBE63_O2(hr_O2_matrix, cal.O);
            hr_O2_umolkg           = hr_O2_umolL ./ hr_den *1000;
            
            HR.PHASE_DELAY_DOXY(~hr_nan)     = hr_d(~hr_nan, iPhase); % predim
            HR.PHASE_DELAY_DOXY_QC(~hr_nan)  = fv.QC;
            HR.TEMP_VOLTAGE_DOXY(~hr_nan)    = hr_d(~hr_nan, iTo);
            HR.TEMP_VOLTAGE_DOXY_QC(~hr_nan) = 3;
            HR.DOXY(~hr_nan)                 = hr_O2_umolkg(~hr_nan);
            thrDOXY = abs(HR.DOXY) > crazy_val & ~hr_nan; % Unrealistic bad value
            HR.DOXY(thrDOXY) = crazy_val; % SET TO crazy bad value
            HR.DOXY_QC(~hr_nan)              = 3;
            %HR.DOXY_QC(thrDOXY) = 4;
            HR.DOXY_QC(LRQF_S | LRQF_T)      = 4; % VERY BAD S or T
            HR.TEMP_DOXY(~hr_nan)            = hr_O2_T(~hr_nan);
            HR.TEMP_DOXY_QC(~hr_nan)         = 3;
        end
        
        clear hr_O2_matrix hr_O2_umolL hr_O2_T hr_O2_umolkg
        
        
        if isfield(QC,'O')
            % !! ONE TIME GAIN CORRECTION ONLY !!
            %             LR.DOXY_ADJUSTED(~lr_nan)  = LR.DOXY(~lr_nan) .* QC.O.steps(3);
            QCD = [LR.PRES(~lr_nan), LR.TEMP(~lr_nan), LR.PSAL(~lr_nan), LR.DOXY(~lr_nan)];
            LR.DOXY_ADJUSTED(~lr_nan) = apply_QC_corr(QCD, d.sdn, QC.O);
            tlrDOXY_ADJ = abs(LR.DOXY_ADJUSTED) > crazy_val & ~lr_nan;
            LR.DOXY_ADJUSTED(tlrDOXY_ADJ) = crazy_val; % SET TO crazy bad value
            LR.DOXY_ADJUSTED_QC(~lr_nan) = 1; % 2 = probably good
            %LR.DOXY_ADJUSTED_QC(tlrDOXY_ADJ) = 4; % crazy val bad
            LR.DOXY_ADJUSTED_ERROR(~lr_nan) = LR.DOXY_ADJUSTED(~lr_nan) * 0.01;
            if r_hr> 0
                %HR.DOXY_ADJUSTED(~hr_nan)  = HR.DOXY(~hr_nan) .* QC.O.steps(3);
                QCD = [HR.PRES(~hr_nan), HR.TEMP(~hr_nan), HR.PSAL(~hr_nan), HR.DOXY(~hr_nan)];
                HR.DOXY_ADJUSTED(~hr_nan) = apply_QC_corr(QCD, d.sdn, QC.O);
                thrDOXY_ADJ = abs(HR.DOXY_ADJUSTED) > crazy_val & ~hr_nan;
                HR.DOXY_ADJUSTED(thrDOXY_ADJ) = crazy_val; % SET TO crazy bad value
                HR.DOXY_ADJUSTED_QC(~hr_nan) = 1; % 2 = probably good
                %HR.DOXY_ADJUSTED_QC(thrDOXY_ADJ) = 4; % crazyval bad
                HR.DOXY_ADJUSTED_QC(HRQF_S | HRQF_T) = 4; % VERY BAD S or T
                HR.DOXY_ADJUSTED_ERROR(~hr_nan) = HR.DOXY_ADJUSTED(~hr_nan) * 0.01;
            end
            
            %             INFO.DOXY_SCI_CAL_EQU  = 'DOXY_ADJUSTED=DOXY*G';
            %             INFO.DOXY_SCI_CAL_COEF = ['G=', ...
            %                 num2str(QC.O.steps(1,3),'%0.4f')];
            INFO.DOXY_SCI_CAL_EQU  = 'DOXY_ADJUSTED=DOXY*G; G = G_INIT + G_DRIFT*(JULD_PROF - JULD_INIT)/365';
            % QC matrix entry relevant to current cycle.
            steptmp = find(QC.O.steps(:,2)<=INFO.cast,1,'last');
            juld_prof = INFO.sdn-datenum(1950,01,01); %convert to JULD
            juld_init = QC.O.steps(steptmp,1)-datenum(1950,01,01); %convert to JULD
            INFO.DOXY_SCI_CAL_COEF = ['G_INIT = ', ...
                num2str(QC.O.steps(steptmp,3),'%0.4f'),...
                '; G_DRIFT = ',num2str(QC.O.steps(steptmp,5),'%0.4f'),...
                '; JULD_PROF = ',num2str(juld_prof,'%9.4f'),...
                '; JULD_INIT = ',num2str(juld_init,'%9.4f')];
            if ~isempty(d.air)
                INFO.DOXY_SCI_CAL_COM  = ['G determined from float' ...
                    ' measurements in air. See Johnson et al.,2015,', ...
                    'doi:10.1175/JTECH-D-15-0101.1'];
            else
                INFO.DOXY_SCI_CAL_COM  = ['G determined by surface' ...
                    ' measurement comparison to World Ocean Atlas 2009.', ...
                    'See Takeshita et al.2013,doi:10.1002/jgrc.20399'];
            end
        end
        
        if ~isempty(d.air) & sum(d.air) ~= 0 % 0 means ice detection on
            zero_fill = d.air(:,1) * 0; % make array of zeros
            O2 = calc_O2_4ARGO(zero_fill, d.air(:,1), zero_fill, ...
                d.air(:,2), cal.O);
            AIR_O2 = O2; % �mol/L still
            clear O2
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'O');
        t_bio = LR.DOXY ~= fv.bio;
        tST   = LR.PSAL_QC == 4 | LR.TEMP_QC == 4 | LR.PRES_QC == 4; % Bad S or T will affect O2
        t_chk = t_bio & (LR.DOXY < RCR.O(1)|LR.DOXY > RCR.O(2) | tST);
        tz = LR.PRES == max(LR.PRES) & t_bio; % 1st sample at depth always bad on NAVIS
        
        
        LR.DOXY_QC(t_chk) = 4;
        LR.DOXY_QC(tz) = 4;
        LR.PHASE_DELAY_DOXY_QC(t_chk) = 4;
        LR.PHASE_DELAY_DOXY_QC(tz) = 4;
        LR.DOXY_QC(t_bio) = LR.DOXY_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.PHASE_DELAY_DOXY_QC(t_bio) = LR.PHASE_DELAY_DOXY_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        
        
        
        t_bio = LR.DOXY_ADJUSTED ~= fv.bio;
        tST   = LR.PSAL_ADJUSTED_QC == 4 | LR.TEMP_ADJUSTED_QC == 4 | ...
            LR.PRES_ADJUSTED_QC == 4 ; % Bad S or T will affect O2
        t_chk = t_bio & ...
            (LR.DOXY_ADJUSTED < RC.O(1)|LR.DOXY_ADJUSTED > RC.O(2) | tST);
        tz = LR.PRES == max(LR.PRES) & t_bio; %
        LR.DOXY_ADJUSTED_QC(t_chk) = 4;
        LR.DOXY_ADJUSTED_QC(tz) = 4;
        LR.DOXY_ADJUSTED_QC(t_bio) = LR.DOXY_ADJUSTED_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        
        if r_hr > 0
            t_bio = HR.DOXY ~= fv.bio;
            tST   = HR.PSAL_QC == 4 | HR.TEMP_QC == 4 | HR.PRES_QC == 4; % Bad S or T will affect O2
            t_chk = t_bio & (HR.DOXY < RCR.O(1)|HR.DOXY > RCR.O(2) | tST);
            
            HR.DOXY_QC(t_chk) = 4;
            HR.PHASE_DELAY_DOXY_QC(t_chk) = 4;
            HR.DOXY_QC(t_bio) = HR.DOXY_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.PHASE_DELAY_DOXY_QC(t_bio) = HR.PHASE_DELAY_DOXY_QC(t_bio) ...
                * ~BSLflag + BSLflag*theflag;
            
            t_bio = HR.DOXY_ADJUSTED ~= fv.bio;
            tST   = HR.PSAL_ADJUSTED_QC == 4 | HR.TEMP_ADJUSTED_QC == 4 ...
                | HR.PRES_ADJUSTED_QC == 4; % Bad S or T will affect O2
            t_chk = t_bio & ...
                (HR.DOXY_ADJUSTED < RC.O(1)|HR.DOXY_ADJUSTED > RC.O(2) | tST);
            HR.DOXY_ADJUSTED_QC(t_chk) = 4;
            HR.DOXY_ADJUSTED_QC(t_bio) = HR.DOXY_ADJUSTED_QC(t_bio) * ...
                ~BSLflag + BSLflag*theflag;
        end
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        % DO A SPIKE TEST ON VALUES, IF SPIKES ARE IDENTIFIED, SET QF TO 4
        % (BAD).  BGC_spiketest screens for nans and fill values and pre-identified bad values.
        %
        % RUN TEST ON LR DOXY AND DOXY_ADJUSTED
        QCscreen_O = LR.DOXY_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.DOXY],'O2',dirs.cal,fv.bio,QCscreen_O);
        if ~isempty(spike_inds)
            LR.DOXY_QC(spike_inds) = quality_flags;
            disp(['LR.DOXY QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.DOXY SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        QCscreen_Oadj = LR.DOXY_ADJUSTED_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.DOXY_ADJUSTED],'O2',dirs.cal,fv.bio,QCscreen_Oadj);
        if ~isempty(spike_inds)
            LR.DOXY_ADJUSTED_QC(spike_inds) = quality_flags;
            disp(['LR.DOXY_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.DOXY_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        clear QCscreen_O QCscreenOadj
        %
        % RUN TEST ON HR DOXY AND DOXY_ADJUSTED
        QCscreen_O = HR.DOXY_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.DOXY],'O2',dirs.cal,fv.bio,QCscreen_O);
        if ~isempty(spike_inds)
            HR.DOXY_QC(spike_inds) = quality_flags;
            disp(['HR.DOXY QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO HR.DOXY SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        QCscreen_Oadj = HR.DOXY_ADJUSTED_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.DOXY_ADJUSTED],'O2',dirs.cal,fv.bio,QCscreen_Oadj);
        if ~isempty(spike_inds)
            HR.DOXY_ADJUSTED_QC(spike_inds) = quality_flags;
            disp(['HR.DOXY_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO HR.DOXY_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        clear QCscreen_O QCscreenOadj
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
    end
    clear lr_nan hr_nan
    
    % ****************************************************************
    % CALCULATE CHLOROPHYLL CONCENTRATION (�g/L or mg/m^3)
    % ****************************************************************
    if ~isempty(iChl)
        %disp(INFO.FlbbMode)
        % Predim variables with fill values then adjust as needed
        LR.FLUORESCENCE_CHLA    = fill0 + fv.bio;
        LR.FLUORESCENCE_CHLA_QC = fill0 + fv.QC;
        LR.CHLA                 = fill0 + fv.bio;
        LR.CHLA_QC              = fill0 + fv.QC;
        LR.CHLA_ADJUSTED        = fill0 + fv.bio;
        LR.CHLA_ADJUSTED_QC     = fill0 + fv.QC;
        LR.CHLA_ADJUSTED_ERROR  = fill0 + fv.bio;
        INFO.CHLA_SCI_CAL_EQU   = 'not applicable';
        INFO.CHLA_SCI_CAL_COEF  = 'not applicable';
        INFO.CHLA_SCI_CAL_COM   = 'not applicable';
        INFO.CHLA_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR.FLUORESCENCE_CHLA    = fill0_hr + fv.bio;
        HR.FLUORESCENCE_CHLA_QC = fill0_hr + fv.QC;
        HR.CHLA                 = fill0_hr + fv.bio;
        HR.CHLA_QC              = fill0_hr + fv.QC;
        HR.CHLA_ADJUSTED        = fill0_hr + fv.bio;
        HR.CHLA_ADJUSTED_QC     = fill0_hr + fv.QC;
        HR.CHLA_ADJUSTED_ERROR  = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iChl)); % NaN's in data if any
        LR.FLUORESCENCE_CHLA(~lr_nan)    = lr_d(~lr_nan,iChl);
        LR.FLUORESCENCE_CHLA_QC(~lr_nan) = fv.QC;
        
        if r_hr >0
            hr_nan = isnan(hr_d(:,iChl)); % NaN's in data if any
            HR.FLUORESCENCE_CHLA(~hr_nan)    = hr_d(~hr_nan,iChl);
            HR.FLUORESCENCE_CHLA_QC(~hr_nan) = fv.QC;
        end
        
        
        if isfield(cal,'CHL') % Sensor could be bad so maybe no cal info
            LR.CHLA(~lr_nan) = (lr_d(~lr_nan,iChl) - cal.CHL.ChlDC) .* ...
                cal.CHL.ChlScale;
            LR.CHLA_QC(~lr_nan) =  3; % 3 do not use w/o adjusting
            
            if r_hr > 0
                HR.CHLA(~hr_nan) = (hr_d(~hr_nan,iChl) - cal.CHL.ChlDC) ...
                    .* cal.CHL.ChlScale;
                HR.CHLA_QC(~hr_nan) =  3; % 3 do not use w/o adjusting
            end
            
            % ADJUSTED DATA BASED ON ADMT18 CONCENSUS -WILL BE UPDATED
            % WITHIN THE YEAR - jp 12/13/2017
            
            % 1st CHECK FOR IN SITU DARKS & TRY AND GET THEM IF NOT THERE
            if ~isfield(cal.CHL, 'SWDC')
                %SWDC = get_CHLdark(MBARI_ID_str, dirs, 5); % 1st 5 good profiles
                SWDC = get_CHLdark(cal.info, dirs, 5); % 1st 5 good profiles
                if ~isempty(SWDC)
                    cal.CHL.SWDC = SWDC; % add structure to cal file
                    save(fp_cal,'cal') % update cal file
                    disp(['Cal file updated: ',fp_cal]);
                end
            end
            
            % FIGURE OUT WHICH DC TO USE BUT ALWAYS CREATE ADJUSTED CHL
            % DATA IF RAW EXISTS
            if isfield(cal.CHL, 'SWDC')
                CHL_DC = cal.CHL.SWDC.DC;
            else
                CHL_DC = cal.CHL.ChlDC; % NO IN SITU DARKS YET OR EVER
            end
            
            LR.CHLA_ADJUSTED(~lr_nan) = (lr_d(~lr_nan,iChl) - ...
                CHL_DC) .* cal.CHL.ChlScale ./ 2;
            LR.CHLA_ADJUSTED_QC(~lr_nan) =  2;
            LR.CHLA_ADJUSTED_ERROR(~lr_nan) = ...
                abs(LR.CHLA_ADJUSTED(~lr_nan) * 2);
            
            if r_hr > 0 % ONLY NEED TO DO NPQ ON HR DATA, LR DEEP ONLY
                HR.CHLA_ADJUSTED(~hr_nan) = (hr_d(~hr_nan,iChl) - ...
                    CHL_DC) .* cal.CHL.ChlScale ./ 2;
                HR.CHLA_ADJUSTED_QC(~hr_nan) =  2;
                
                % NPQ NEXT
                NPQ_CHL = HR.CHLA_ADJUSTED;
                NPQ_CHL(hr_nan) = NaN; % fill back to NaN
                %                 NPQ = get_NPQcorr([INFO.sdn, nanmean(INFO.gps,1)], ...
                %                 %INFO.gps now includes sdn, TM 10/27/20
                NPQ = get_NPQcorr(mean(INFO.gps,1,'omitnan'), ...
                    [hr_d(:,[iP,iT,iS]),NPQ_CHL], dirs);
                NPQ.data(hr_nan,2:end) = fv.bio; % nan back to fill
                
                if ~isempty(NPQ.data)
                    iXing   = find(strcmp('Xing_MLD',NPQ.hdr) == 1);
                    iSPIKE  = find(strcmp('CHLspike',NPQ.hdr) == 1);
                    tNPQ = hr_d(:,iP) <= NPQ.XMLDZ;
                    HR.CHLA_ADJUSTED(tNPQ & ~hr_nan) = ...
                        NPQ.data(tNPQ & ~hr_nan,iXing) + ...
                        NPQ.data(tNPQ & ~hr_nan,iSPIKE);
                    HR.CHLA_ADJUSTED_QC(tNPQ & ~hr_nan) =  5;
                end
                
                HR.CHLA_ADJUSTED_ERROR(~hr_nan) = ...
                    abs(HR.CHLA_ADJUSTED(~hr_nan) * 2);
            end
            
            INFO.CHLA_SCI_CAL_EQU  = ['CHLA_ADJUSTED=CHLA/A, '...
                'NPQ corrected (Xing et al., 2012), spike profile ', ...
                'added back in'];
            INFO.CHLA_SCI_CAL_COEF = 'A=2';
            INFO.CHLA_SCI_CAL_COM  =['A is best estimate ', ...
                'from Roesler et al., 2017, doi: 10.1002/lom3.10185'];
            
            
            % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
            [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'CHL');
            t_bio   = LR.CHLA ~= fv.bio;
            t_chk   = t_bio & (LR.CHLA < RCR.CHL(1)|LR.CHLA > RCR.CHL(2));
            LR.FLUORESCENCE_CHLA_QC(t_bio) = LR.FLUORESCENCE_CHLA_QC(t_bio) ...
                * ~BSLflag + BSLflag*theflag;
            LR.CHLA_QC(t_bio) = LR.CHLA_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            LR.CHLA_QC(t_chk) = 4;
            LR.FLUORESCENCE_CHLA_QC(t_chk) = 4;
            
            if r_hr > 0
                t_bio = HR.CHLA ~= fv.bio;
                t_chk = t_bio & (HR.CHLA < RCR.CHL(1)|HR.CHLA > RCR.CHL(2));
                HR.FLUORESCENCE_CHLA_QC(t_bio) = HR.FLUORESCENCE_CHLA_QC(t_bio) ...
                    * ~BSLflag + BSLflag*theflag;
                HR.CHLA_QC(t_bio) = HR.CHLA_QC(t_bio) * ~BSLflag + BSLflag*theflag;
                HR.FLUORESCENCE_CHLA_QC(t_chk) = 4;
                HR.CHLA_QC(t_chk) = 4;
            end
            
            
            if isfield(cal.CHL, 'SWDC')
                t_bio = LR.CHLA_ADJUSTED ~= fv.bio;
                t_chk = t_bio & ...
                    (LR.CHLA_ADJUSTED < RC.CHL(1)|LR.CHLA_ADJUSTED > RC.CHL(2));
                LR.CHLA_ADJUSTED_QC(t_bio) = LR.CHLA_ADJUSTED_QC(t_bio) ...
                    * ~BSLflag + BSLflag*theflag;
                LR.CHLA_ADJUSTED_QC(t_chk) = 4;
                
                if r_hr > 0
                    t_bio = HR.CHLA_ADJUSTED ~= fv.bio;
                    t_chk = t_bio & ...
                        (HR.CHLA_ADJUSTED < RC.CHL(1)|HR.CHLA_ADJUSTED > RC.CHL(2));
                    HR.CHLA_ADJUSTED_QC(t_bio) = HR.CHLA_ADJUSTED_QC(t_bio) ...
                        * ~BSLflag + BSLflag*theflag;
                    HR.CHLA_ADJUSTED_QC(t_chk) = 4;
                end
            end
        end
        clear lr_nan hr_nan
    end
    
    % ****************************************************************
    % CALCULATE PARTICLE BACKSCATTER COEFFICIENT (700)FROM VOLUME
    % SCATTERING FUNCTION (VSF) (m^-1)
    % ****************************************************************
    if ~isempty(iBb)
        LR_VSF                       = fill0 + fv.bio; % pre dimmension
        LR_BETA_SW                   = fill0 + fv.bio;
        LR.BETA_BACKSCATTERING700    = fill0 + fv.bio;
        LR.BETA_BACKSCATTERING700_QC = fill0 + fv.QC;
        LR.BBP700                    = fill0 + fv.bio;
        LR.BBP700_QC                 = fill0 + fv.QC;
        LR.BBP700_ADJUSTED           = fill0 + fv.bio;
        LR.BBP700_ADJUSTED_QC        = fill0 + fv.QC;
        LR.BBP700_ADJUSTED_ERROR     = fill0 + fv.bio;
        INFO.BBP700_SCI_CAL_EQU   = 'not applicable';
        INFO.BBP700_SCI_CAL_COEF  = 'not applicable';
        INFO.BBP700_SCI_CAL_COM   = 'not applicable';
        INFO.BBP700_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR_VSF                       = fill0_hr + fv.bio;
        HR_BETA_SW                   = fill0_hr + fv.bio;
        HR.BETA_BACKSCATTERING700    = fill0_hr + fv.bio;
        HR.BETA_BACKSCATTERING700_QC = fill0_hr + fv.QC;
        HR.BBP700                    = fill0_hr + fv.bio;
        HR.BBP700_QC                 = fill0_hr + fv.QC;
        HR.BBP700_ADJUSTED           = fill0_hr + fv.bio;
        HR.BBP700_ADJUSTED_QC        = fill0_hr + fv.QC;
        HR.BBP700_ADJUSTED_ERROR     = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iBb)); % NaN's in data if any
        LR.BETA_BACKSCATTERING700(~lr_nan) = lr_d(~lr_nan,iBb); % counts
        LR.BETA_BACKSCATTERING700_QC(~lr_nan) = fv.QC;
        
        % CP data exists
        if r_hr > 0
            hr_nan = isnan(hr_d(:,iBb)); % NaN's in data if any
            HR.BETA_BACKSCATTERING700(~hr_nan) = hr_d(~hr_nan,iBb); % counts
            HR.BETA_BACKSCATTERING700_QC(~hr_nan) = fv.QC;
        end
        
        
        if isfield(cal,'BB') % Sensor could be bad so maybe no cal info
            % VOLUME SCATTERING FUNCTION (VSF) (m^-1 sr^-1)
            LR_VSF(~lr_nan) = (lr_d(~lr_nan, iBb) - cal.BB.BetabDC) ...
                .* cal.BB.BetabScale;
            % NOW CALCULATE PARTICLE BACKSCATTER COEFFICIENT
            %X  = 1.13*2*pi; % (Barnes and Antoine, 2014)
            %X   = 1.17*2*pi; % (email from E. Boss 24 May 2016 this is for FLBB)
            %(Proc. Bio-Argo particle backscattering at the DAC level
            %Version 1.2, July 21th 2016
            X      = 1.142*2*pi; % MCOMS @ 700
            LAMBDA = 700; % wavelength
            THETA  = 149; % meas. angle, BBP processing doc July 2016
            DELTA  = 0.039;      % depolarization ratio
            
            BETA_SW_ind = find(lr_nan == 0);
            if ~isempty(BETA_SW_ind)
                for ct = 1:size(BETA_SW_ind,1)
                    [LR_BETA_SW(BETA_SW_ind(ct)), b90sw, bsw] = ...
                        betasw_ZHH2009(LAMBDA,lr_d(BETA_SW_ind(ct),iT), ...
                        THETA, lr_d(BETA_SW_ind(ct),iS), DELTA);
                end
            end
            LR.BBP700(~lr_nan)    = (LR_VSF(~lr_nan) - ...
                LR_BETA_SW(~lr_nan)) * X; %b_bp m^-1
            LR.BBP700_QC(~lr_nan) = 2;
            if r_hr > 0 % CP data exists
                % VOLUME SCATTERING FUNCTION (VSF) (m^-1 sr^-1)
                HR_VSF(~hr_nan) = (hr_d(~hr_nan, iBb) - cal.BB.BetabDC) ...
                    .* cal.BB.BetabScale;
                % NOW CALCULATE PARTICLE BACKSCATTER COEFFICIENT
                BETA_SW_ind = find(hr_nan == 0);
                if ~isempty(BETA_SW_ind)
                    for ct = 1:size(BETA_SW_ind,1)
                        [HR_BETA_SW(BETA_SW_ind(ct)), b90sw, bsw] = ...
                            betasw_ZHH2009(LAMBDA,hr_d(BETA_SW_ind(ct),iT), ...
                            THETA, hr_d(BETA_SW_ind(ct),iS), DELTA);
                    end
                end
                HR.BBP700(~hr_nan) = (HR_VSF(~hr_nan) - ...
                    HR_BETA_SW(~hr_nan)) * X; %b_bp m^-1
                HR.BBP700_QC(~hr_nan) = 2;
            end
            
            % CALCULATE ADJUSTED DATA
            % ...6/10/21 START POPULATING BBP700_ADJUSTED WITH BBP
            % DIRECTLY!!!  KEEP ORIGINAL BLOCK IN CASE AN ACTUAL ADJUSTMENT
            % GETS IMPLEMENTED/STORED IN THE QC MATRIX.
            LR.BBP700_ADJUSTED(~lr_nan) = LR.BBP700(~lr_nan);
            LR.BBP700_ADJUSTED_QC(~lr_nan) = 1;
            LR.BBP700_ADJUSTED_ERROR(~lr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            if r_hr > 0
                HR.BBP700_ADJUSTED(~hr_nan) = HR.BBP700(~hr_nan);
                HR.BBP700_ADJUSTED_QC(~hr_nan) = 1;
                HR.BBP700_ADJUSTED_ERROR(~hr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            end
            INFO.BBP700_SCI_CAL_EQU  = 'BBP700_ADJUSTED=BBP700';
            INFO.BBP700_SCI_CAL_COEF = [''];
            INFO.BBP700_SCI_CAL_COM  =['BBP700_ADJUSTED is being filled with BBP700 directly in real time.  Adjustment method may be enhanced in the future.'];
            %             if isfield(QC,'BB')
            %                 QCD = [LR.PRES, LR.TEMP, LR.PSAL, LR.BBP700];
            %                 LR.BBP700_ADJUSTED(~lr_nan) = ...
            %                     apply_QC_corr(QCD(~lr_nan,:), d.sdn, QC.BB);
            %                 LR.BBP700_ADJUSTED_QC(~lr_nan) =  2;
            %                 LR.BBP700_ADJUSTED_ERROR(~lr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            %                 INFO.BBP700_SCI_CAL_EQU  = 'BBP700_ADJUSTED=BBP700*A-B';
            %                 INFO.BBP700_SCI_CAL_COEF = ['A=', ...
            %                     num2str(QC.BB.steps(3),'%0.4f'),',B=',...
            %                     num2str(QC.BB.steps(4),'%0.4f')];
            %                 INFO.BBP700_SCI_CAL_COM  =['A and B determined by comparison', ...
            %                     ' to discrete samples from post deployment calibration',...
            %                     ' rosette cast'];
            %                 if r_hr > 0
            %                     QCD = [HR.PRES, HR.TEMP, HR.PSAL, HR.BBP700];
            %                     HR.BBP700_ADJUSTED(~hr_nan) = ...
            %                         apply_QC_corr(QCD(~hr_nan,:), d.sdn, QC.BB);
            %                     HR.BBP700_ADJUSTED_QC(~hr_nan) =  2;
            %                     HR.BBP700_ADJUSTED_ERROR(~hr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            %                 end
            %             end
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        [BSLflag, theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'BBP');
        t_bio   = LR.BBP700 ~= fv.bio;
        t_chk = t_bio &(LR.BBP700 < RCR.BB700(1)|LR.BBP700 > RCR.BB700(2));
        LR.BETA_BACKSCATTERING700_QC(t_bio) = ...
            LR.BETA_BACKSCATTERING700_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.BBP700_QC(t_bio) = LR.BBP700_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.BETA_BACKSCATTERING700_QC(t_chk) = 4;
        LR.BBP700_QC(t_chk) = 4;
        
        t_bio = LR.BBP700_ADJUSTED ~= fv.bio;
        t_chk = t_bio & (LR.BBP700_ADJUSTED < RC.BB700(1)| ...
            LR.BBP700_ADJUSTED > RC.BB700(2));
        LR.BBP700_ADJUSTED_QC(t_bio) = LR.BBP700_ADJUSTED_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        LR.BBP700_ADJUSTED_QC(t_chk) = 4;
        if r_hr > 0
            t_bio = HR.BBP700 ~= fv.bio;
            t_chk = t_bio & ...
                (HR.BBP700 < RCR.BB700(1)|HR.BBP700 > RCR.BB700(2));
            HR.BETA_BACKSCATTERING700_QC(t_bio) = ...
                HR.BETA_BACKSCATTERING700_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.BBP700_QC(t_bio) = HR.BBP700_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.BETA_BACKSCATTERING700_QC(t_chk) = 4;
            HR.BBP700_QC(t_chk) = 4;
            
            t_bio = HR.BBP700_ADJUSTED ~= fv.bio;
            t_chk = t_bio & (HR.BBP700_ADJUSTED < RC.BB700(1)| ...
                HR.BBP700_ADJUSTED > RC.BB700(2));
            HR.BBP700_ADJUSTED_QC(t_bio) = HR.BBP700_ADJUSTED_QC(t_bio) ...
                * ~BSLflag + BSLflag*theflag;
            HR.BBP700_ADJUSTED_QC(t_chk) = 4;
        end
        
        clear LR_BETA_SW HR_BETA_SW BETA_SW_ind X HR_VSF LR_VSF
        clear lr_nan hr_nan ct b90sw bsw
        
    end
    
    % ****************************************************************
    % CALCULATE CDOM (ppb)
    % ****************************************************************
    if ~isempty(iCdm) &&  isempty(regexp(MBARI_ID_str, cdom_bbp532_chk, 'once'))
        
        LR.FLUORESCENCE_CDOM    = fill0 + fv.bio;
        LR.FLUORESCENCE_CDOM_QC = fill0 + fv.QC;
        LR.CDOM                 = fill0 + fv.bio;
        LR.CDOM_QC              = fill0 + fv.QC;
        LR.CDOM_ADJUSTED        = fill0 + fv.bio;
        LR.CDOM_ADJUSTED_QC     = fill0 + fv.QC;
        LR.CDOM_ADJUSTED_ERROR  = fill0 + fv.bio;
        INFO.CDOM_SCI_CAL_EQU   = 'not applicable';
        INFO.CDOM_SCI_CAL_COEF  = 'not applicable';
        INFO.CDOM_SCI_CAL_COM   = 'not applicable';
        INFO.CDOM_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR.FLUORESCENCE_CDOM    = fill0_hr + fv.bio;
        HR.FLUORESCENCE_CDOM_QC = fill0_hr + fv.QC;
        HR.CDOM                 = fill0_hr + fv.bio;
        HR.CDOM_QC              = fill0_hr + fv.QC;
        HR.CDOM_ADJUSTED        = fill0_hr + fv.bio;
        HR.CDOM_ADJUSTED_QC     = fill0_hr + fv.QC;
        HR.CDOM_ADJUSTED_ERROR  = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iCdm)); % NaN's in data if any
        LR.FLUORESCENCE_CDOM(~lr_nan)    = lr_d(~lr_nan,iCdm);
        LR.FLUORESCENCE_CDOM_QC(~lr_nan) = fv.QC;
        
        if r_hr > 0
            hr_nan = isnan(hr_d(:,iCdm)); % NaN's in data if any
            HR.FLUORESCENCE_CDOM(~hr_nan)    = hr_d(~hr_nan,iCdm);
            HR.FLUORESCENCE_CDOM_QC(~hr_nan) = fv.QC;
        end
        
        if isfield(cal,'CDOM') % Sensor could be bad so maybe no cal info
            LR.CDOM(~lr_nan)  = (lr_d(~lr_nan,iCdm) - cal.CDOM.CDOMDC) ...
                .* cal.CDOM.CDOMScale;
            LR.CDOM_QC(~lr_nan) =  3; % 3 do not use w/o adjusting
            if r_hr > 0
                HR.CDOM(~hr_nan)  = (hr_d(~hr_nan,iCdm) - cal.CDOM.CDOMDC) ...
                    .* cal.CDOM.CDOMScale;
                HR.CDOM_QC(~hr_nan) =  3; % 3 do not use w/o adjusting
            end
            
            % NO ADJUSTED DATA YET !!!! THESE ARE PLACE HOLDERS FOR NOW !!!!
            if isfield(QC,'CDOM')
                LR.CDOM_ADJUSTED(~lr_nan)       = fv.bio;
                LR.CDOM_ADJUSTED_QC(~lr_nan)    = fv.QC;
                LR.CDOM_ADJUSTED_ERROR(~lr_nan) =  fv.bio; % PLACE HOLDER FOR NOW
                if r_hr > 0
                    HR.CDOM_ADJUSTED(~hr_nan)       = fv.bio;
                    HR.CDOM_ADJUSTED_QC(~hr_nan)    = fv.QC;
                    HR.CDOM_ADJUSTED_ERROR(~hr_nan) =  fv.bio; % PLACE HOLDER FOR NOW
                end
                
            end
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        [BSLflag,theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'CDOM');
        t_bio = LR.CDOM ~= fv.bio;
        t_chk = t_bio & (LR.CDOM < RCR.CDOM(1)|LR.CDOM > RCR.CDOM(2));
        LR.FLUORESCENCE_CDOM_QC(t_bio) = LR.FLUORESCENCE_CDOM_QC(t_bio) ...
            * ~BSLflag + BSLflag*theflag;
        LR.CDOM_QC(t_bio) = LR.CDOM_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.FLUORESCENCE_CDOM_QC(t_chk) = 4;
        LR.CDOM_QC(t_chk) = 4;
        
        t_bio = LR.CDOM_ADJUSTED ~= fv.bio;
        t_chk = t_bio & ...
            (LR.CDOM_ADJUSTED < RC.CDOM(1)|LR.CDOM_ADJUSTED > RC.CDOM(2));
        LR.CDOM_ADJUSTED_QC(t_bio) = LR.CDOM_ADJUSTED_QC(t_bio) *  ...
            ~BSLflag + BSLflag*theflag;
        LR.CDOM_ADJUSTED_QC(t_chk) = 4;
        
        if r_hr > 0
            t_bio = HR.CDOM ~= fv.bio;
            t_chk = t_bio & (HR.CDOM < RCR.CDOM(1)|HR.CDOM > RCR.CDOM(2));
            HR.FLUORESCENCE_CDOM_QC(t_bio) = HR.FLUORESCENCE_CDOM_QC(t_bio) ...
                * ~BSLflag + BSLflag*theflag;
            HR.CDOM_QC(t_bio) = HR.CDOM_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.FLUORESCENCE_CDOM_QC(t_chk) = 4;
            HR.CDOM_QC(t_chk) = 4;
            
            t_bio = HR.CDOM_ADJUSTED ~= fv.bio;
            t_chk = t_bio & ...
                (HR.CDOM_ADJUSTED < RC.CDOM(1)|HR.CDOM_ADJUSTED > RC.CDOM(2));
            HR.CDOM_ADJUSTED_QC(t_bio) = HR.CDOM_ADJUSTED_QC(t_bio) *  ...
                ~BSLflag + BSLflag*theflag;
            HR.CDOM_ADJUSTED_QC(t_chk) = 4;
        end
        
        clear QCD lr_nan hr_nan
    end
    
    % ****************************************************************
    % CALCULATE PARTICLE BACKSCATTER COEFFICIENT (532)FROM VOLUME
    % SCATTERING FUNCTION (VSF) (m^-1) FOR FLOAT 0565
    % CDOM IS REALLT BBP532
    % !!! BAD SENSOR LIST NOT IMPLEMENTED FOR FLOAT 0565 -jp 06/26/2017 !!!
    % ****************************************************************
    if ~isempty(iCdm) && ~isempty(regexp(MBARI_ID_str, cdom_bbp532_chk, 'once'))
        disp([MBARI_ID_str,'MCOMs FDOMchannel is really BBP532'])
        LR_VSF                       = fill0 + fv.bio; % pre dimmension
        LR_BETA_SW                   = fill0 + fv.bio;
        LR.BETA_BACKSCATTERING532    = fill0 + fv.bio;
        LR.BETA_BACKSCATTERING532_QC = fill0 + fv.QC;
        LR.BBP532                    = fill0 + fv.bio;
        LR.BBP532_QC                 = fill0 + fv.QC;
        LR.BBP532_ADJUSTED           = fill0 + fv.bio;
        LR.BBP532_ADJUSTED_QC        = fill0 + fv.QC;
        LR.BBP532_ADJUSTED_ERROR     = fill0 + fv.bio;
        INFO.BBP532_SCI_CAL_EQU   = 'not applicable';
        INFO.BBP532_SCI_CAL_COEF  = 'not applicable';
        INFO.BBP532_SCI_CAL_COM   = 'not applicable';
        INFO.BBP532_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR_VSF                       = fill0_hr + fv.bio;
        HR_BETA_SW                   = fill0_hr + fv.bio;
        HR.BETA_BACKSCATTERING532    = fill0_hr + fv.bio;
        HR.BETA_BACKSCATTERING532_QC = fill0_hr + fv.QC;
        HR.BBP532                    = fill0_hr + fv.bio;
        HR.BBP532_QC                 = fill0_hr + fv.QC;
        HR.BBP532_ADJUSTED           = fill0_hr + fv.bio;
        HR.BBP532_ADJUSTED_QC        = fill0_hr + fv.QC;
        HR.BBP532_ADJUSTED_ERROR     = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iCdm)); % NaN's in data if any
        LR.BETA_BACKSCATTERING532(~lr_nan) = lr_d(~lr_nan,iCdm); % counts
        LR.BETA_BACKSCATTERING532_QC(~lr_nan) = fv.QC;
        
        % CP data exists
        if r_hr > 0
            hr_nan = isnan(hr_d(:,iCdm)); % NaN's in data if any
            HR.BETA_BACKSCATTERING532(~hr_nan) = hr_d(~hr_nan,iCdm); % counts
            HR.BETA_BACKSCATTERING532_QC(~hr_nan) = fv.QC;
        end
        
        
        if isfield(cal,'CDOM') % Sensor could be bad so maybe no cal info
            % VOLUME SCATTERING FUNCTION (VSF) (m^-1 sr^-1)
            LR_VSF(~lr_nan) = (lr_d(~lr_nan, iCdm) - cal.CDOM.CDOMDC) ...
                .* cal.CDOM.CDOMScale;
            % NOW CALCULATE PARTICLE BACKSCATTER COEFFICIENT
            
            %(Proc. Bio-Argo particle backscattering at the DAC level
            % Version 1.2, July 21th 2016
            X      = 1.142*2*pi; % MCOMS @ 532 ???
            LAMBDA = 532; % wavelength
            THETA  = 149; % meas. angle, BBP processing doc July 2016
            DELTA  = 0.039;      % depolarization ratio
            
            BETA_SW_ind = find(lr_nan == 0);
            if ~isempty(BETA_SW_ind)
                for ct = 1:size(BETA_SW_ind,1)
                    [LR_BETA_SW(BETA_SW_ind(ct)), b90sw, bsw] = ...
                        betasw_ZHH2009(LAMBDA,lr_d(BETA_SW_ind(ct),iT), ...
                        THETA, lr_d(BETA_SW_ind(ct),iS), DELTA);
                end
            end
            LR.BBP532(~lr_nan)    = (LR_VSF(~lr_nan) - ...
                LR_BETA_SW(~lr_nan)) * X; %b_bp m^-1
            LR.BBP532_QC(~lr_nan) = 2;
            
            if r_hr > 0 % CP data exists
                % VOLUME SCATTERING FUNCTION (VSF) (m^-1 sr^-1)
                HR_VSF(~hr_nan) = (hr_d(~hr_nan, iCdm) - cal.CDOM.CDOMDC) ...
                    .* cal.CDOM.CDOMScale;
                % NOW CALCULATE PARTICLE BACKSCATTER COEFFICIENT (700)
                BETA_SW_ind = find(hr_nan == 0);
                if ~isempty(BETA_SW_ind)
                    for ct = 1:size(BETA_SW_ind,1)
                        [HR_BETA_SW(BETA_SW_ind(ct)), b90sw, bsw] = ...
                            betasw_ZHH2009(LAMBDA,hr_d(BETA_SW_ind(ct),iT), ...
                            THETA, hr_d(BETA_SW_ind(ct),iS), DELTA);
                    end
                end
                HR.BBP532(~hr_nan) = (HR_VSF(~hr_nan) - ...
                    HR_BETA_SW(~hr_nan)) * X; %b_bp m^-1
                HR.BBP532_QC(~hr_nan) = 2;
            end
            
            % CALCULATE ADJUSTED DATA
            % ...6/10/21 START POPULATING BBP700_ADJUSTED WITH BBP
            % DIRECTLY!!!  KEEP ORIGINAL BLOCK IN CASE AN ACTUAL ADJUSTMENT
            % GETS IMPLEMENTED/STORED IN THE QC MATRIX.
            LR.BBP532_ADJUSTED(~lr_nan) = LR.BBP532(~lr_nan);
            LR.BBP532_ADJUSTED_QC(~lr_nan) = 1;
            LR.BBP532_ADJUSTED_ERROR(~lr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            if r_hr > 0
                HR.BBP532_ADJUSTED(~hr_nan) = HR.BBP532(~hr_nan);
                HR.BBP532_ADJUSTED_QC(~hr_nan) = 1;
                HR.BBP532_ADJUSTED_ERROR(~hr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            end
            INFO.BBP532_SCI_CAL_EQU  = 'BBP532_ADJUSTED=BBP532';
            INFO.BBP532_SCI_CAL_COEF = [''];
            INFO.BBP532_SCI_CAL_COM  =['BBP532_ADJUSTED is being filled with BBP532 directly in real time.  Adjustment method may be enhanced in the future.'];
            %             if isfield(QC,'CDOM')
            %                 QCD = [LR.PRES, LR.TEMP, LR.PSAL, LR.BBP532];
            %                 LR.BBP532_ADJUSTED(~lr_nan) = ...
            %                     apply_QC_corr(QCD(~lr_nan,:), d.sdn, QC.CDOM);
            %                 LR.BBP532_ADJUSTED_QC(~lr_nan) =  2;
            %                 LR.BBP532_ADJUSTED_ERROR(~lr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            %                 INFO.BBP532_SCI_CAL_EQU  = 'BBP532_ADJUSTED=BBP532*A-B';
            %                 INFO.BBP532_SCI_CAL_COEF = ['A=', ...
            %                     num2str(QC.CDOM.steps(3),'%0.4f'),',B=',...
            %                     num2str(QC.CDOM.steps(4),'%0.4f')];
            %                 INFO.BBP532_SCI_CAL_COM  =['A and B determined by comparison', ...
            %                     ' to discrete samples from post deployment calibration',...
            %                     ' rosette cast'];
            %                 if r_hr > 0
            %                     QCD = [HR.PRES, HR.TEMP, HR.PSAL, HR.BBP532];
            %                     HR.BBP532_ADJUSTED(~hr_nan) = ...
            %                         apply_QC_corr(QCD(~hr_nan,:), d.sdn, QC.CDOM);
            %                     HR.BBP532_ADJUSTED_QC(~hr_nan) =  2;
            %                     HR.BBP532_ADJUSTED_ERROR(~hr_nan) = fv.bio; % PLACE HOLDER FOR NOW
            %                 end
            %             end
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        t_chk = LR.BBP532 ~= fv.bio & ...
            (LR.BBP532 < RCR.BB532(1)|LR.BBP532 > RCR.BB532(2));
        LR.BBP532_QC(t_chk) = 4;
        LR.BETA_BACKSCATTERING532_QC(t_chk) = 4;
        
        t_chk = LR.BBP532_ADJUSTED ~= fv.bio & ...
            (LR.BBP532_ADJUSTED < RC.BB532(1)| ...
            LR.BBP532_ADJUSTED > RC.BB532(2));
        LR.BBP532_ADJUSTED_QC(t_chk) = 4;
        
        if r_hr > 0
            t_chk = HR.BBP532 ~= fv.bio & ...
                (HR.BBP532 < RCR.BB532(1)|HR.BBP532 > RCR.BB532(2));
            HR.BBP532_QC(t_chk) = 4;
            HR.BETA_BACKSCATTERING532_QC(t_chk) = 4;
            
            t_chk = HR.BBP532_ADJUSTED ~= fv.bio & ...
                (HR.BBP532_ADJUSTED < RC.BB532(1)| ...
                HR.BBP532_ADJUSTED > RC.BB532(2));
            HR.BBP532_ADJUSTED_QC(t_chk) = 4;
        end
        
        
        clear LR_BETA_SW HR_BETA_SW BETA_SW_ind X HR_VSF LR_VSF
        clear lr_nan hr_nan ct b90sw bsw
    end
    
    % ****************************************************************
    % CALCULATE pH (�mol / kg scale)
    % ****************************************************************
    if ~isempty(iphV)
        LR.VRS_PH                          = fill0 + fv.bio;
        LR.VRS_PH_QC                       = fill0 + fv.QC;
        LR.TEMP_PH                         = fill0 + fv.bio;
        LR.TEMP_PH_QC                      = fill0 + fv.QC;
        LR.PH_IN_SITU_FREE                 = fill0 + fv.bio;
        LR.PH_IN_SITU_FREE_QC              = fill0 + fv.QC;
        LR.PH_IN_SITU_TOTAL                = fill0 + fv.bio;
        LR.PH_IN_SITU_TOTAL_QC             = fill0 + fv.QC;
        LR.PH_IN_SITU_TOTAL_ADJUSTED       = fill0 + fv.bio;
        LR.PH_IN_SITU_TOTAL_ADJUSTED_QC    = fill0 + fv.QC;
        LR.PH_IN_SITU_TOTAL_ADJUSTED_ERROR = fill0 + fv.bio;
        INFO.PH_SCI_CAL_EQU  = 'not applicable';
        INFO.PH_SCI_CAL_COEF = 'not applicable';
        INFO.PH_SCI_CAL_COM  = 'not applicable';
        INFO.PH_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        HR.VRS_PH                          = fill0_hr + fv.bio;
        HR.VRS_PH_QC                       = fill0_hr + fv.QC;
        HR.TEMP_PH                         = fill0_hr + fv.bio;
        HR.TEMP_PH_QC                      = fill0_hr + fv.QC;
        HR.PH_IN_SITU_FREE                 = fill0_hr + fv.bio;
        HR.PH_IN_SITU_FREE_QC              = fill0_hr + fv.QC;
        HR.PH_IN_SITU_TOTAL                = fill0_hr + fv.bio;
        HR.PH_IN_SITU_TOTAL_QC             = fill0_hr + fv.QC;
        HR.PH_IN_SITU_TOTAL_ADJUSTED       = fill0_hr + fv.bio;
        HR.PH_IN_SITU_TOTAL_ADJUSTED_QC    = fill0_hr + fv.QC;
        HR.PH_IN_SITU_TOTAL_ADJUSTED_ERROR = fill0_hr + fv.bio;
        
        lr_nan = isnan(lr_d(:,iphV));
        
        LR.VRS_PH(~lr_nan)     = lr_d(~lr_nan,iphV);
        LR.VRS_PH_QC(~lr_nan)  = fv.QC;
        
        % Newer NAVIS are not using pH temp, using CTD temp instead
        % but the header is there and data = -9.9999 (SBE fill value?)
        % do some book keeping to get CTD temp if no real pH temp
        ph_or_ctd_T = 1;
        if isempty(iphT) % looking to the future: SBE might eliminate pHT
            lr_wrk_temp  = LR.TEMP;
            ph_or_ctd_T = 0;
        else
            LR.TEMP_PH(~lr_nan) = lr_d(~lr_nan,iphT);
            LR.TEMP_PH(LR.TEMP_PH == -9.9999) = fv.bio; % Set SBE fill value to argo fill Value
            LR.TEMP_PH_QC(~lr_nan) = fv.QC; % I don't think this is needed - already defined -jp
            if all(LR.TEMP_PH(~lr_nan) == fv.bio)
                lr_wrk_temp = LR.TEMP; % no pH temp use CTD temp
                ph_or_ctd_T = 0;
            else
                chk_phT = LR.TEMP_PH ~= fv.bio & (LR.TEMP_PH < RCR.PHT(1) ...
                    | LR.TEMP_PH > RCR.PHT(2));
                LR.TEMP_PH_QC(chk_phT) = 4;
                LR.TEMP_PH_QC(LR.TEMP_PH ~= fv.bio & LR.TEMP_PH_QC ~=4) = 1;
                lr_wrk_temp = LR.TEMP_PH;
            end
        end
        
        %         if (strcmp(MBARI_ID_str,'0949STNP')==1) || (strcmp(MBARI_ID_str,'0948STNP')==1) || (strcmp(MBARI_ID_str,'0948STNP2')==1)%pH temp removed from these floats; use ctd temp
        %             LR.TEMP_PH(~lr_nan) = lr_d(~lr_nan,iT);
        %         else
        %             LR.TEMP_PH(~lr_nan)    = lr_d(~lr_nan,iphT); % I param
        %         end
        % %         LR.TEMP_PH(~lr_nan)    = lr_d(~lr_nan,iphT);
        
        [lr_phfree, lr_phtot] = phcalc(LR.VRS_PH(~lr_nan), ...
            LR.PRES(~lr_nan), lr_wrk_temp(~lr_nan), LR.PSAL(~lr_nan), ...
            cal.pH.k0, cal.pH.k2, cal.pH.pcoefs);
        
        if isfield(cal.pH,'secondary_pcoefs')
            [lr_phfree2, lr_phtot2] = phcalc(LR.VRS_PH(~lr_nan), ...
                LR.PRES(~lr_nan), lr_wrk_temp(~lr_nan), LR.PSAL(~lr_nan),...
                cal.pH.k0, cal.pH.k2, cal.pH.secondary_pcoefs);
            
            tz_ph = LR.PRES(~lr_nan) >= cal.pH.secondary_Zlimits(1) & ...
                LR.PRES(~lr_nan) <= cal.pH.secondary_Zlimits(2);
            
            if cal.pH.secondary_Zlimits(1) == 0 % match bottom bound
                ind = find(LR.PRES(~lr_nan) <= ...
                    cal.pH.secondary_Zlimits(2),1,'last');
            else
                ind = find(LR.PRES(~lr_nan) >= ...
                    cal.pH.secondary_Zlimits(1),1,'first');
            end
            free_offset =  lr_phfree(ind) - lr_phfree2(ind); %? jp
            tot_offset  =  lr_phtot(ind)  - lr_phtot2(ind);
            
            lr_phfree(tz_ph) = lr_phfree2(tz_ph) + free_offset;
            lr_phtot(tz_ph)  = lr_phtot2(tz_ph)  + tot_offset;
        end
        
        LR.PH_IN_SITU_FREE(~lr_nan)     = lr_phfree; % I param
        LR.PH_IN_SITU_FREE_QC(~lr_nan)  = fv.QC;
        LR.PH_IN_SITU_FREE_QC(LRQF_S | LRQF_T | LRQF_P) = 4;
        LR.PH_IN_SITU_TOTAL(~lr_nan)    = lr_phtot;
        LR.PH_IN_SITU_TOTAL_QC(~lr_nan) = 3;
        LR.PH_IN_SITU_TOTAL_QC(LRQF_S | LRQF_T | LRQF_P) = 4;
        
        LR_inf = isinf(LR.PH_IN_SITU_FREE); % happens if S = 0
        LR.PH_IN_SITU_FREE(LR_inf)     = 20.1; %UNREAL #
        LR.PH_IN_SITU_FREE_QC(LR_inf)  = 4;
        LR.PH_IN_SITU_TOTAL(LR_inf)    = 20.1; %UNREAL #
        LR.PH_IN_SITU_TOTAL_QC(LR_inf) = 4;
        
        
        if r_hr > 0
            hr_nan = isnan(hr_d(:,iphV));
            HR.VRS_PH(~hr_nan)    = hr_d(~hr_nan,iphV); % I param
            HR.VRS_PH_QC(~hr_nan) = fv.QC;
            
            if ph_or_ctd_T == 0
                hr_wrk_temp  = HR.TEMP;
            else
                HR.TEMP_PH(~hr_nan) = hr_d(~hr_nan,iphT); % I param
                HR.TEMP_PH_QC(HR.TEMP_PH ~= fv.bio) = 4; % 1st set all bad
                %HR.TEMP_PH_QC(~hr_nan) = fv.QC; % I don't think this is needed - already defined -jp
                chk_phT = HR.TEMP_PH ~= fv.bio & HR.TEMP_PH >= RCR.PHT(1) ...
                    & HR.TEMP_PH <= RCR.PHT(2);
                HR.TEMP_PH_QC(chk_phT) = 1; % good temp
                hr_wrk_temp         = HR.TEMP_PH;
            end
            
            
            %             if (strcmp(MBARI_ID_str,'0949STNP')==1) || (strcmp(MBARI_ID_str,'0948STNP')==1) || (strcmp(MBARI_ID_str,'0948STNP2')==1)%pH temp removed from these floats; use ctd temp
            %                 HR.TEMP_PH(~hr_nan) = hr_d(~hr_nan,iT);
            %             else
            %                 HR.TEMP_PH(~hr_nan)    = hr_d(~hr_nan,iphT); % I param
            %             end
            
            
            
            [hr_phfree,hr_phtot] = phcalc(HR.VRS_PH(~hr_nan), ...
                HR.PRES(~hr_nan), hr_wrk_temp(~hr_nan), ...
                HR.PSAL(~hr_nan), cal.pH.k0, cal.pH.k2, cal.pH.pcoefs);
            
            if isfield(cal.pH,'secondary_pcoefs')
                [hr_phfree2,hr_phtot2] = phcalc(HR.VRS_PH(~hr_nan), ...
                    HR.PRES(~hr_nan), hr_wrk_temp(~hr_nan), ...
                    HR.PSAL(~hr_nan), cal.pH.k0, cal.pH.k2, ...
                    cal.pH.secondary_pcoefs);
                
                tz_ph = HR.PRES(~hr_nan) >= cal.pH.secondary_Zlimits(1) & ...
                    HR.PRES(~hr_nan) <= cal.pH.secondary_Zlimits(2);
                
                if cal.pH.secondary_Zlimits(1) == 0 % match bottom bound
                    ind = find(HR.PRES(~hr_nan) <= ...
                        cal.pH.secondary_Zlimits(2),1,'last');
                else
                    ind = find(HR.PRES(~hr_nan) >= ...
                        cal.pH.secondary_Zlimits(1),1,'first');
                end
                
                free_offset =  hr_phfree(ind) - hr_phfree2(ind);
                tot_offset  =  hr_phtot(ind)  - hr_phtot2(ind);
                
                hr_phfree(tz_ph) = hr_phfree2(tz_ph) + free_offset;
                hr_phtot(tz_ph)  = hr_phtot2(tz_ph)  + tot_offset;
            end
            
            HR.PH_IN_SITU_FREE(~hr_nan)     = hr_phfree; % I param
            HR.PH_IN_SITU_FREE_QC(~hr_nan)  = fv.QC;
            HR.PH_IN_SITU_FREE_QC(HRQF_S | HRQF_T | HRQF_P)  = 4;
            HR.PH_IN_SITU_TOTAL(~hr_nan)    = hr_phtot;
            HR.PH_IN_SITU_TOTAL_QC(~hr_nan) = 3;
            HR.PH_IN_SITU_TOTAL_QC(HRQF_S | HRQF_T | HRQF_P)  = 4;
            
            HR_inf = isinf(HR.PH_IN_SITU_FREE); % happens if S = 0
            HR.PH_IN_SITU_FREE(HR_inf)     = 20.1; %UNREAL #
            HR.PH_IN_SITU_FREE_QC(HR_inf)  = 4;
            HR.PH_IN_SITU_TOTAL(HR_inf)    = 20.1; %UNREAL #
            HR.PH_IN_SITU_TOTAL_QC(HR_inf) = 4;
        end
        
        if isfield(QC,'pH')
            QCD = [LR.PRES(~lr_nan), lr_wrk_temp(~lr_nan), ...
                LR.PSAL(~lr_nan), LR.PH_IN_SITU_TOTAL(~lr_nan)];
            LR.PH_IN_SITU_TOTAL_ADJUSTED(~lr_nan) = ...
                apply_QC_corr(QCD, d.sdn, QC.pH);
            LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(~lr_nan)  = 1;
            LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(LRQF_S | LRQF_T | LRQF_P)  = 4;
            LR.PH_IN_SITU_TOTAL_ADJUSTED_ERROR(~lr_nan) = 0.02;
            
            LR.PH_IN_SITU_TOTAL_ADJUSTED(LR_inf) = 20.1; %UNREAL #
            LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(LR_inf) = 4;
            
            INFO.PH_SCI_CAL_EQU  = ['PH_ADJUSTED=PH+[PUMP_OFFSET', ...
                '-SUM(OFFSET(S)+DRIFT(S))]* TCOR'];
            INFO.PH_SCI_CAL_COEF = ['PUMP_OFFSET=Pump may add ', ...
                'interfernece in CP mode,OFFSET(S) and DRIFT(S) from ',...
                'climatology comparisons at 1000m or 1500m,','TCOR=', ...
                '(2+273.15)./(T+273.15)'];
            INFO.PH_SCI_CAL_COM  =['Contact Tanya Maurer ',...
                '(tmaurer@mbari.org) or Josh Plant (jplant@mbari.org) ',...
                'for more information'];
            
            % TEMPORARY ADJUSTED pH FIX 08/02/2016
            % FLOATVIZ pH CALCULATED WITH OLDER FUNCTION. QC STEPS
            % DETERMINED WITH OLD pH VALUES, BUT A CONSTANT OFFSET
            % JP pH - FV pH = 0.0167)
            % Commented out 9/28/16 doing Qc on JP files now
            %             disp(['!!!! APPLYING TEMPORARY pH CORRECTION TO ADJUSTED',...
            %                   ' VALUES (adj_pH = adj_pH - 0.0167)']);
            %             LR.PH_IN_SITU_TOTAL_ADJUSTED(~lr_nan) = ...
            %                 LR.PH_IN_SITU_TOTAL_ADJUSTED(~lr_nan) - 0.0167; % TEMPORARY FIX
            
            if r_hr > 0
                QCD = [HR.PRES(~hr_nan), hr_wrk_temp(~hr_nan), ...
                    HR.PSAL(~hr_nan), HR.PH_IN_SITU_TOTAL(~hr_nan)];
                HR.PH_IN_SITU_TOTAL_ADJUSTED(~hr_nan) = ...
                    apply_QC_corr(QCD, d.sdn, QC.pH);
                
                HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(~hr_nan)    = 1;
                HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(HRQF_S | HRQF_T | HRQF_P)  = 4;
                HR.PH_IN_SITU_TOTAL_ADJUSTED_ERROR(~hr_nan) = 0.02;
                
                HR.PH_IN_SITU_TOTAL_ADJUSTED(HR_inf) = 20.1; %UNREAL #
                HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(HR_inf) = 4;
                
                % TEMPORARY ADJUSTED pH FIX 08/02/2016
                % FLOATVIZ pH CALCULATED WITH OLDER FUNCTION. QC STEPS
                % DETERMINED WITH OLD pH VALUES, BUT A CONSTANT OFFSET
                % JP pH - FV pH = 0.0167)
                %                 HR.PH_IN_SITU_TOTAL_ADJUSTED(~hr_nan) = ...
                %                     HR.PH_IN_SITU_TOTAL_ADJUSTED(~hr_nan) - 0.0167;
            end
            
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        [BSLflag,theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'PH');
        t_bio    = LR.PH_IN_SITU_TOTAL ~= fv.bio;
        chk_wrkT = lr_wrk_temp ~= fv.bio & (lr_wrk_temp < RCR.T(1) ...
            | lr_wrk_temp > RCR.T(2));
        tST     = LR.PSAL_QC == 4 | chk_wrkT | LR.PRES_QC ==4; % Bad S or T will affect pH
        %tST     = LR.PSAL_QC == 4 | LR.TEMP_QC == 4; % Bad S or T will affect pH
        t_chk   = t_bio & (LR.PH_IN_SITU_TOTAL < RCR.PH(1)| ...
            LR.PH_IN_SITU_TOTAL > RCR.PH(2) | tST);
        LR.VRS_PH_QC(t_bio) = LR.VRS_PH_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.PH_IN_SITU_FREE_QC(t_bio) = LR.PH_IN_SITU_FREE_QC(t_bio) ...
            * ~BSLflag + BSLflag*theflag;
        LR.PH_IN_SITU_TOTAL_QC(t_bio) = LR.PH_IN_SITU_TOTAL_QC(t_bio) ...
            * ~BSLflag + BSLflag*theflag;
        LR.PH_IN_SITU_FREE_QC(t_chk) = 4;
        LR.PH_IN_SITU_TOTAL_QC(t_chk) = 4;
        LR.VRS_PH_QC(t_chk) = 4;
        
        %         if INFO.cast == 2, pause, end % TESTING
        
        t_bio   = LR.PH_IN_SITU_TOTAL_ADJUSTED ~= fv.bio;
        tST     = LR.PSAL_ADJUSTED_QC == 4 | chk_wrkT | LR.PRES_ADJUSTED_QC == 4; % Bad S or T will affect pH
        %tST     = LR.PSAL_ADJUSTED_QC == 4 | LR.TEMP_ADJUSTED_QC == 4; % Bad S or T will affect pH
        t_chk = t_bio & (LR.PH_IN_SITU_TOTAL_ADJUSTED < RC.PH(1)| ...
            LR.PH_IN_SITU_TOTAL_ADJUSTED > RC.PH(2) | tST);
        LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_bio) = ...
            LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_chk) = 4;
        
        
        if r_hr > 0
            t_bio   = HR.PH_IN_SITU_TOTAL ~= fv.bio;
            chk_wrkT = hr_wrk_temp ~= fv.bio & (hr_wrk_temp < RCR.T(1) ...
                | hr_wrk_temp > RCR.T(2));
            tST     = HR.PSAL_QC == 4 | chk_wrkT | HR.PRES_QC == 4; % Bad S or T will affect pH
            %tST     = HR.PSAL_QC == 4 | HR.TEMP_QC == 4; % Bad S or T will affect pH
            t_chk = t_bio & (HR.PH_IN_SITU_TOTAL < RCR.PH(1)| ...
                HR.PH_IN_SITU_TOTAL > RCR.PH(2)| tST);
            HR.VRS_PH_QC(t_bio) = HR.VRS_PH_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.PH_IN_SITU_TOTAL_QC(t_bio) = HR.PH_IN_SITU_TOTAL_QC(t_bio) ...
                * ~BSLflag + BSLflag*theflag;
            HR.PH_IN_SITU_TOTAL_QC(t_chk) = 4;
            HR.VRS_PH_QC(t_chk) = 4;
            
            t_bio   = HR.PH_IN_SITU_TOTAL_ADJUSTED ~= fv.bio;
            tST     = HR.PSAL_ADJUSTED_QC == 4 | chk_wrkT | HR.PRES_ADJUSTED_QC == 4; % Bad S or T will affect pH
            %tST     = HR.PSAL_ADJUSTED_QC == 4 | HR.TEMP_ADJUSTED_QC == 4; % Bad S or T will affect pH
            t_chk = t_bio & (HR.PH_IN_SITU_TOTAL_ADJUSTED < RC.PH(1)| ...
                HR.PH_IN_SITU_TOTAL_ADJUSTED > RC.PH(2) | tST);
            HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_bio) = ...
                HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_bio) * ~BSLflag + BSLflag*theflag;
            HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(t_chk) = 4;
        end
        
        
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        % FINALLY DO A SPIKE TEST ON VALUES, IF SPIKES ARE IDENTIFIED, SET QF TO 4
        % (BAD).  BGC_spiketest screens for nans and fill values.
        %
        %%%LOW RES FIRST%%%
        %
        % RUN TEST ON RAW PH_IN_SITU_TOTAL
        QCscreen_phT = LR.PH_IN_SITU_TOTAL_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.PH_IN_SITU_TOTAL],'PH',dirs.cal,fv.bio,QCscreen_phT);
        if ~isempty(spike_inds)
            % Could add optional code to compare qf already assigned (ie in range
            % checks above), and qf assigned during spiketest.  Keep
            % whichever is greater.  (At this point, I'm pre-screening the vector using
            % current quality flags.  Screening occurs within Function.  Currently assigning 4 (bad) to spikes, although may
            % be modified in the future).  5/22/18. TM.
            %spikeQF = LR.PH_INSITU_FREE_QC(spike_inds) < quality_flags;
            %LR.PH_INSITU_FREE_QC(spike_inds(spikeQF)) = quality_flags(spikeQF);
            LR.PH_IN_SITU_TOTAL_QC(spike_inds) = quality_flags;
            disp(['LR.PH_IN_SITU_TOTAL QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.PH_IN_SITU_TOTAL SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        %
        % RUN TEST ON QC PH_IN_SITU_TOTAL_ADJUSTED
        QCscreen_phTadj = LR.PH_IN_SITU_TOTAL_ADJUSTED_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.PH_IN_SITU_TOTAL_ADJUSTED],'PH',dirs.cal,fv.bio,QCscreen_phTadj);
        if ~isempty(spike_inds)
            LR.PH_IN_SITU_TOTAL_ADJUSTED_QC(spike_inds) = quality_flags;
            disp(['LR.PH_IN_SITU_TOTAL_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.PH_IN_SITU_TOTAL_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        clear QCscreen_phF QCscreen_phT QCscreen_phTadj
        %%%HI RES NEXT%%%
        %
        % RUN TEST ON RAW PH_IN_SITU_TOTAL
        QCscreen_phT = HR.PH_IN_SITU_TOTAL_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.PH_IN_SITU_TOTAL],'PH',dirs.cal,fv.bio,QCscreen_phT);
        if ~isempty(spike_inds)
            HR.PH_IN_SITU_TOTAL_QC(spike_inds) = quality_flags;
            disp(['HR.PH_IN_SITU_TOTAL QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO HR.PH_IN_SITU_TOTAL SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        %
        % RUN TEST ON QC PH_IN_SITU_TOTAL_ADJUSTED
        QCscreen_phTadj = HR.PH_IN_SITU_TOTAL_ADJUSTED_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.PH_IN_SITU_TOTAL_ADJUSTED],'PH',dirs.cal,fv.bio,QCscreen_phTadj);
        if ~isempty(spike_inds)
            HR.PH_IN_SITU_TOTAL_ADJUSTED_QC(spike_inds) = quality_flags;
            disp(['HR.PH_IN_SITU_TOTAL_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO HR.PH_IN_SITU_TOTAL_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        clear QCscreen_phF QCscreen_phT QCscreen_phTadj
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        
        clear lr_phfree lr_phtot hr_phfree hr_phtot QCD
    end
    
    % ****************************************************************
    % CALCULATE NITRATE (�mol / kg scale)
    % DO DEPTH CORRECTION Ist
    % CONVERT TO �mol/kg
    % ****************************************************************
    if ~isempty(iNO3)
        LR.NITRATE                      = fill0 + fv.bio;
        LR.NITRATE_QC                   = fill0 + fv.QC;
        LR.UV_INTENSITY_DARK_NITRATE    = fill0 + fv.bio;
        LR.UV_INTENSITY_DARK_NITRATE_QC = fill0 + fv.QC;
        LR.UV_INTENSITY_NITRATE         = fill0 + fv.bio;
        LR.UV_INTENSITY_NITRATE_QC      = fill0 + fv.QC;
        
        LR.NITRATE_ADJUSTED             = fill0 + fv.bio;
        LR.NITRATE_ADJUSTED_QC          = fill0 + fv.QC;
        LR.NITRATE_ADJUSTED_ERROR       = fill0 + fv.bio;
        INFO.NITRATE_SCI_CAL_EQU  = 'not applicable';
        INFO.NITRATE_SCI_CAL_COEF = 'not applicable';
        INFO.NITRATE_SCI_CAL_COM  = 'not applicable';
        INFO.NITRATE_DATA_MODE  = 'R'; %"not applicable" is not acceptable for this field, should be 'R' (per Coriolis)
        
        % IF ISUS FILE & CAL INFO EXIST TRY AND PROCESS IT
        if exist([dirs.temp, NO3_file],'file') && isfield(cal,'N')%
            spec = parse_NO3msg([dirs.temp,NO3_file]); % return struct
            if ~isempty(spec.P) %check fields; if P empty, isus file was likely empty
                if ~isempty(HR.PRES) && ~isempty(HR.TEMP) && ~isempty(HR.PSAL)
                    [spec, CTD_for_no3, CTDmn_for_no3] = getTRUE_SUNAtemp(spec,HR.TEMP,HR.PRES,HR.PSAL,0);
                else
                    disp(['CANNOT RUN "getTRUE_SUNAtemp" for float ',MBARI_ID_str,'. HR.PRES, HR.TEMP or HR.PSAL are empty!'])
                end
            end
            UV_INTEN = spec.UV_INTEN;
            if ~isempty(UV_INTEN)
                % [SDN, DarkCur, Pres, Temp, Sal, NO3, BL_int,BL_slope,
                %  RMS_ER, Wl~240, ABS~240] !!! NITRATE STILL �mol/L !!!
                NO3  = calc_FLOAT_NO3(spec, cal.N, 1); % ESW P corr
                %NO3  = calc_APEX_NO3_JP(spec, cal.N, 0); % NO P corr
                
                IX = (size(NO3,1):-1:1)'; % FLIP SHALLOW TO DEEP FOR ARGO
                %[B,IX]   = sort(NO3(:,3)); % SORT SHALLOW TO DEEP FOR ARGO
                NO3      = NO3(IX,:);
                UV_INTEN = UV_INTEN(IX,:);
                clear B IX
            end
        elseif ~isfield(cal,'N')
            disp('No calibration info to process nitrate with')
        else
            disp([dirs.temp, NO3_file,' not found!!'])
        end
        
        if exist('NO3', 'var') == 1
            % MATCH NITRATE DEPTHS TO CTD DEPTHS IF LENGTHS DIFFERENT
            % MISSING SPECTRA  AND NO3 CONC. SET TO NaN
            % could also  replace missing NO3 from *.isus rwith *.msg
            if size(LR.PRES,1) ~= size(NO3,1) % Mismatch in sample lengths
                cS       = size(spec.UV_INTEN,2); % cols of WL's
                rP       = size(LR.PRES,1); % # of CTD samples (*.msg)
                [rN, cN] = size(NO3); % RN = # of isus samples (*.isus)
                disp(['*.isus(',num2str(rN),') & *.msg(',num2str(rP), ...
                    ') sample counts not equal for ',msg_file])
                NO3tmp   = ones(rP,cN)* NaN;
                spectmp  = ones(rP,cS)* fv.bio;
                % fill msg file data then replace with NO3 data
                %NO3tmp(:,3:6) = [LR.PRES, LR.TEMP, LR.PSAL lr_d(:,iNO3)];
                NO3tmp(:,3:5) = [LR.PRES, LR.TEMP, LR.PSAL];
                
                for i = 1: rP
                    ind  = find(NO3(:,3) == LR.PRES(i),1,'first');
                    if ~isempty(ind)
                        NO3tmp(i,:)  = NO3(ind,:);
                        spectmp(i,:) = UV_INTEN(ind,:);
                    end
                end
                NO3      = NO3tmp;
                
                UV_INTEN = spectmp; % n x m matrix
                clear rP rN cN NO3tmp i
            end
            
            t_nan = isnan(NO3(:,6));
            % CHECK FIT ERROR AND BASELINE ABSORBANCE
            tABS08 = NO3(:,11) > 0.8; %ABS240 > 0.8 (QF=3)
            tABS11 = NO3(:,9) > 0.003 | NO3(:,11) > 1.1; % RMS & ABS240 (QF=4)
            
            LR.UV_INTENSITY_DARK_NITRATE    = NO3(:,2);
            LR.UV_INTENSITY_DARK_NITRATE(t_nan) = fv.bio;
            LR.UV_INTENSITY_DARK_NITRATE_QC = fill0 + fv.QC;
            
            LR.UV_INTENSITY_NITRATE    =  UV_INTEN;
            LR.UV_INTENSITY_NITRATE_QC =  UV_INTEN * 0 + fv.QC;
            
            NpotT  = theta(NO3(:,3), NO3(:,4), NO3(:,5),0);
            N_den  = density(NO3(:,5), NpotT);
            %NO3_kg = NO3(:,6) ./ N_den * 1000;
            
            
            % ********************************************************
            % CALCULATE NITRATE IN umol/L FOR PRESSURE = 0
            % (vs in situ p). ISUS calibrated at p = 0 but
            % ISUS MEASURES IN SITU CONCENTRATION SO ISUS NO3 SLIGHTLY
            % GREATER THAN BOTTLE or SURFACE NO3 (p=0) AT DEPTH
            % (more moles NO3 per liter at depth)
            % NO3(p=0) = N03(p=z) *[density(S,T,p=0) /density(S,T,p@z)]
            
            NO3_p0 = NO3(:,6) .* sw_dens(NO3(:,5),NpotT,0) ./ ...
                sw_dens(NO3(:,5),NO3(:,4),NO3(:,3));
            
            NO3_p0_kg     = NO3_p0 ./ N_den * 1000; % �mol/kg
            
            LR.NITRATE = NO3_p0_kg;
            LR.NITRATE(t_nan) = fv.bio;
            
            
            % QC RAW
            LR.NITRATE_QC = fill0 + 3; % ZERO = NO QC
            LR.NITRATE_QC(t_nan) = fv.QC;
            LR.NITRATE_QC(~t_nan & tABS11) = 4;
            LR.NITRATE_QC(LRQF_S | LRQF_T | LRQF_P) = 4; % BAD S or T
            
            % ********************************************************
            % APPLY QC CORRECTIONS
            % CORRECTIONS DETERMINED ON �mol/L scale so adjust on that
            % scale and then convert
            if isfield(QC,'N')
                QCD = [LR.PRES, LR.TEMP, LR.PSAL,NO3_p0_kg];
                LR.NITRATE_ADJUSTED = fill0 + fv.bio;
                LR.NITRATE_ADJUSTED(~t_nan) = apply_QC_corr(QCD(~t_nan,:), d.sdn, QC.N);
                
                LR.NITRATE_ADJUSTED_QC = fill0 + 1;
                LR.NITRATE_ADJUSTED_QC(t_nan) = fv.QC;
                LR.NITRATE_ADJUSTED_QC(~t_nan & tABS08) = 3; %Bad ABS240
                LR.NITRATE_ADJUSTED_QC(~t_nan & tABS11) = 4; % Really bad abs or RMS
                LR.NITRATE_ADJUSTED_QC(LRQF_S | LRQF_T) = 4;
                
                LR.NITRATE_ADJUSTED_ERROR = (abs(LR.NITRATE - ...
                    LR.NITRATE_ADJUSTED)) * 0.1 + 0.5;
                LR.NITRATE_ADJUSTED_ERROR(t_nan) = fv.bio;
                
                INFO.NITRATE_SCI_CAL_EQU  = ['NITRATE_ADJUSTED=', ...
                    '[NITRATE-SUM(OFFSET(S)+DRIFT(S))]/GAIN'];
                INFO.NITRATE_SCI_CAL_COEF = ['OFFSET(S) and DRIFT(S) ', ...
                    'from climatology comparisons at 1000m or 1500m. GAIN ',...
                    'from surface/deep comparison where surface values ',...
                    'are known'];
                INFO.NITRATE_SCI_CAL_COM  =['Contact Tanya Maurer ',...
                    '(tmaurer@mbari.org) or Josh Plant (jplant@mbari.org) ',...
                    'for more information'];
            end
            clear QCD NO3 UV_INTEN
        end
        
        % DO A FINAL RANGE CHECK ON VALUES, IF BAD SET QF = 4
        [BSLflag,theflag] = isbadsensor(BSL, MBARI_ID_str, INFO.cast, 'N');
        t_bio = LR.NITRATE ~= fv.bio;
        tST     = LR.PSAL_QC == 4 | LR.TEMP_QC == 4 | LR.PRES_QC == 4; % Bad S or T will affect nitrate
        t_chk = t_bio &(LR.NITRATE < RCR.NO3(1)| LR.NITRATE > RCR.NO3(2) | tST);
        LR.NITRATE_QC(t_bio) = LR.NITRATE_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.UV_INTENSITY_DARK_NITRATE_QC(t_bio) = ...
            LR.UV_INTENSITY_DARK_NITRATE_QC(t_bio) * ~BSLflag + BSLflag*theflag;
        LR.NITRATE_QC(t_chk) = 4;
        LR.UV_INTENSITY_DARK_NITRATE_QC(t_chk)  = 4;
        
        t_bio = LR.NITRATE_ADJUSTED ~= fv.bio;
        tST     = LR.PSAL_ADJUSTED_QC == 4 | LR.TEMP_ADJUSTED_QC == 4 | LR.PRES_ADJUSTED_QC == 4; % Bad S or T will affect nitrate
        t_chk = t_bio & (LR.NITRATE_ADJUSTED < RC.NO3(1)| ...
            LR.NITRATE_ADJUSTED > RC.NO3(2) | tST);
        LR.NITRATE_ADJUSTED_QC(t_bio) = LR.NITRATE_ADJUSTED_QC(t_bio) * ...
            ~BSLflag + BSLflag*theflag;
        LR.NITRATE_ADJUSTED_QC(t_chk) = 4;
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        % DO A SPIKE TEST ON VALUES, IF SPIKES ARE IDENTIFIED, SET QF TO 4
        % (BAD).  BGC_spiketest screens for nans and fill values.
        %
        %%% DO LOW RES FIRST%%%
        % RUN TEST ON RAW NITRATE
        QCscreen_N = LR.NITRATE_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.NITRATE],'NO3',dirs.cal,fv.bio,QCscreen_N);
        if ~isempty(spike_inds)
            LR.NITRATE_QC(spike_inds) = quality_flags;
            disp(['LR.NITRATE QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.NITRATE SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        %
        % RUN TEST ON QC NITRATE_ADJUSTED
        QCscreen_Nadj = LR.NITRATE_ADJUSTED_QC == 4; % screen for BAD data already assigned.
        [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[LR.PRES LR.NITRATE_ADJUSTED],'NO3',dirs.cal,fv.bio,QCscreen_Nadj);
        if ~isempty(spike_inds)
            LR.NITRATE_ADJUSTED_QC(spike_inds) = quality_flags;
            disp(['LR.NITRATE_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            %         else
            %             disp(['NO LR.NITRATE_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
        end
        clear QCscreen_N QCscreen_Nadj
        %%% DO HI RES NEXT %%%
        %  I don't think there is any Hi-Res Nitrate for any NAVIS floats.
        %  Keep it in here for now with the added check, just in case.
        % RUN TEST ON RAW NITRATE
        if isfield(HR,'NITRATE') == 1
            QCscreen_N = HR.NITRATE_QC == 4; % screen for BAD data already assigned.
            [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.NITRATE],'NO3',dirs.cal,fv.bio,QCscreen_N);
            if ~isempty(spike_inds)
                HR.NITRATE_QC(spike_inds) = quality_flags;
                disp(['HR.NITRATE QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
                %             else
                %                 disp(['NO HR.NITRATE SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            end
            %
            % RUN TEST ON QC NITRATE_ADJUSTED
            QCscreen_Nadj = HR.NITRATE_ADJUSTED_QC == 4; % screen for BAD data already assigned.
            [spike_inds, quality_flags] = BGC_spiketest(MBARI_ID_str,str2double(cast_num),[HR.PRES HR.NITRATE_ADJUSTED],'NO3',dirs.cal,fv.bio,QCscreen_Nadj);
            if ~isempty(spike_inds)
                HR.NITRATE_ADJUSTED_QC(spike_inds) = quality_flags;
                disp(['HR.NITRATE_ADJUSTED QUALITY FLAGS ADJUSTED FOR IDENTIFIED SPIKES, PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
                %             else
                %                 disp(['NO HR.NITRATE_ADJUSTED SPIKES IDENTIFIED FOR PROFILE ',cast_num,' FLOAT ',MBARI_ID_str,'.'])
            end
            clear QCscreen_N QCscreen_Nadj
        end
        % -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
        
        clear tchk tABS08 tABS11 NO3
    end
    
    % ********************************************************************
    % INCORPORATE QUALITY FLAGS FROm EXISTING ODV FILES IF THEY ARE GREATER
    % THAN ZERO. BRUTE FORCE LOOK UP. USE PRESUURE AND TEMPERATURE TO MAKE
    % MATCH AND KEEP TOLERENCES TIGHT
    %              !!! EVENTUALLY MAKE THIS A FUNCTION !!!
    % ********************************************************************
    % BUILD LOOK UP TABLE: ODV VARIABLES AND MATCHING ARGO VARIABLES
    
    %         QCvars(1,:) = {'Oxygen[�M]'         'DOXY'}; % OLD FLOATVIZ
    %         QCvars(2,:) = {'Nitrate[�M]'        'NITRATE'};
    %         QCvars(3,:) = {'Chlorophyll[�g/l]'  'CHLA'};
    %         QCvars(4,:) = {'BackScatter[/m/sr]' 'BBP700'};
    %         QCvars(5,:) = {'CDOM[ppb]'          'CDOM'};
    %         QCvars(6,:) = {'pHinsitu[Total]'    'PH_IN_SITU_TOTAL'};
    
    QCvars(1,:) = {'Temperature[�C]'    'TEMP'}; % NEW FLOATVIZ
    QCvars(2,:) = {'Salinity[pss]'      'PSAL'};
    QCvars(3,:) = {'Oxygen[�mol/kg]'    'DOXY'};
    QCvars(4,:) = {'Nitrate[�mol/kg]'    'NITRATE'};
    QCvars(5,:) = {'Chl_a[mg/m^3]'      'CHLA'};
    QCvars(6,:) = {'b_bp700[1/m]'       'BBP700'};
    QCvars(7,:) = {'pHinsitu[Total]'    'PH_IN_SITU_TOTAL'};
    QCvars(8,:) = {'b_bp532[1/m]'       'BBP532'};
    QCvars(9,:) = {'CDOM[ppb]'          'CDOM'};
    
    % DO UNADJUSTED QF's FIRST
    if ~isempty(FV_data)
        iQF = find(strcmp(FV_data.hdr,'QF') == 1); % FIND QF column indices
        tFV         = FV_data.data(:,2) == INFO.cast;
        FV_cast     = FV_data.data(tFV,:);   % get an exisitng FloatViz cast
        FV_QF_sum   = sum(FV_cast(:,iQF),1); % sum of QF columns
        if sum(FV_QF_sum) > 0        % ANY ODV QF FLAGS GREATER THAN ZERO?
            indQF   = iQF(FV_QF_sum > 0); % FV QF colums w/ non zero flags
            for QF_ct = 1 : size(indQF,2)
                % CHECK IF IT IS A PARAMETER TO BE INSPECTED
                ind = strcmp(FV_data.hdr{indQF(QF_ct)-1},QCvars(:,1));
                % FLOAVIZ VAR MATCHES LIST, LR VAR EXISTS, GET MATCHING QF's
                if sum(ind) > 0 && isfield(LR,QCvars{ind,2})
                    % P,T and QC col of interest
                    ODV_QF  = [FV_cast(:,6),FV_cast(:,8), ...
                        FV_cast(:,indQF(QF_ct))]; % P, T & QC
                    % CONVERT BACK TO ARGO VALUES
                    if strcmp(QCvars{ind,2},'BBP700') == 1 || strcmp(QCvars{ind,2},'BBP532') == 1 
                        ODV_QF(ODV_QF(:,3) == 4,3) = 2;
                        ODV_QF(ODV_QF(:,3) == 8,3) = 4;
                    else
                        ODV_QF(ODV_QF(:,3) == 4,3) = 3;
                        ODV_QF(ODV_QF(:,3) == 8,3) = 4;
                    end
                    % LR (NEED TO DO LR & HR FOR NAVIS)
                    ARGO_QF = [LR.PRES, LR.TEMP, LR.([QCvars{ind,2},'_QC'])];
                    ct = 0;
                    for i = 1:size(ARGO_QF,1) % line by line just in case
                        dP = abs(ODV_QF(:,1) - ARGO_QF(i,1)); % press
                        dT = abs(ODV_QF(:,2) - ARGO_QF(i,2)); % temp
                        min_dP = min(dP); % this should be 0 but def < 1m
                        min_dT = min(dT);
                        if min_dP > 1.1% poor match
                            disp(['Poor QF match for ARGO LR.PRES = ', ...
                                num2str(ARGO_QF(i,1))])
                            continue
                        end
                        t1 = dP == min_dP & dT == min_dT; % there should only be one
                        if ODV_QF(t1,3) > ARGO_QF(i,3) % ODV QF worse than ARGO
                            ARGO_QF(i,3) = ODV_QF(t1,3); % replace argo w/ ODV
                            ct =ct+1;
                        end
                    end
                    LR.([QCvars{ind,2},'_QC']) = ARGO_QF(:,3); %update structure
                    if ct > 0
                        disp([num2str(ct), ' LR QC flags added from ODV ', ...
                            'file for ', QCvars{ind,2}, '_QC'])
                    end
                    
                    % HR (NEED TO DO LR & HR FOR NAVIS)
                    if isfield(HR,[QCvars{ind,2},'_QC']) && ...
                            ~isempty(HR.([QCvars{ind,2},'_QC']))
                        ARGO_QF = [HR.PRES, HR.TEMP, HR.([QCvars{ind,2},'_QC'])];
                        ct = 0;
                        for i = 1:size(ARGO_QF,1) % line by line just in case
                            dP = abs(ODV_QF(:,1) - ARGO_QF(i,1)); % press
                            dT = abs(ODV_QF(:,2) - ARGO_QF(i,2)); % temp
                            min_dP = min(dP); % this should be 0 but def < 1m
                            min_dT = min(dT);
                            if min_dP > 0.75 % poor match
                                disp(['Poor QF match for ARGO HR.PRES = ', ...
                                    num2str(ARGO_QF(i,1))])
                                continue
                            end
                            t1 = dP == min_dP & dT == min_dT; % there should only be one
                            if ODV_QF(t1,3) > ARGO_QF(i,3) % ODV QF worse than ARGO
                                ARGO_QF(i,3) = ODV_QF(t1,3); % replace argo w/ ODV
                                ct =ct+1;
                            end
                        end
                        HR.([QCvars{ind,2},'_QC']) = ARGO_QF(:,3); %update structure
                        if ct > 0
                            disp([num2str(ct), ' HR QC flags added from ODV ', ...
                                'file for ', QCvars{ind,2}, '_QC'])
                        end
                    end
                end
            end
            clear tFV FV_cast FV_QF_sum indQF QF_ct ODV_QF ARGO_QF ct i dP t1
            clear min_dP min_dT dT
        end
    end
    
    % NOW DO ADJUSTED DATA QF's
    if ~isempty(FV_QCdata) && FVQC_flag == 1
        iQF = find(strcmp(FV_QCdata.hdr,'QF') == 1); % QF column indices
        tFVQC       = FV_QCdata.data(:,2) == INFO.cast;
        FVQC_cast   = FV_QCdata.data(tFVQC,:); % get individual QF FloatViz cast
        FVQC_QF_sum = sum(FVQC_cast(:,iQF),1); % sum of cast QF columns
        
        if sum(FVQC_QF_sum) > 0      % ANY ODV QF FLAGS GREATER THAN ZERO?
            indQF   = iQF(FVQC_QF_sum > 0); % ODV QF colums w/ non zero flags
            for QF_ct = 1 : size(indQF,2)
                ind = strcmp(FV_QCdata.hdr{indQF(QF_ct)-1},QCvars(:,1));
                % FLOAVIZ VAR MATCHES LIST, GET MATCHING QF's
                if sum(ind) > 0 && isfield(LR,[QCvars{ind,2},'_ADJUSTED'])
                    ODV_QF  = [FVQC_cast(:,6), FVQC_cast(:,8), ...
                        FVQC_cast(:,indQF(QF_ct))];% P&T&QC
                    if strcmp(QCvars{ind,2},'BBP700') == 1 || strcmp(QCvars{ind,2},'BBP532') == 1 
                        ODV_QF(ODV_QF(:,3) == 4,3) = 2;
                        ODV_QF(ODV_QF(:,3) == 8,3) = 4;
                    else
                        ODV_QF(ODV_QF(:,3) == 4,3) = 3; % CONVERT TO ARGO VALUES
                        ODV_QF(ODV_QF(:,3) == 8,3) = 4; % CONVERT TO ARGO VALUES
                    end
                    % FLOAVIZ VAR MATCHES LIST, LR VAR EXISTS, GET MATCHING QF's
                    
                    % LR ADJUSTED
                    ARGO_QF = [LR.PRES, LR.TEMP, LR.([QCvars{ind,2},'_ADJUSTED_QC'])];
                    ct = 0;
                    for i = 1:size(ARGO_QF,1) % line by line just in case
                        dP = abs(ODV_QF(:,1) - ARGO_QF(i,1));
                        dT = abs(ODV_QF(:,2) - ARGO_QF(i,2));
                        min_dP = min(dP); % this should be 0 but def < 1m
                        min_dT = min(dT);
                        if min_dP > 1.1 % poor match
                            disp(['Poor LR QF match for ARGO PRES = ', ...
                                num2str(ARGO_QF(i,1))])
                            continue
                        end
                        t1 = dP == min_dP & dT == min_dT; % there should only be one
                        if ODV_QF(t1,3) > ARGO_QF(i,3) % ODV QF worse than ARGO
                            ARGO_QF(i,3) = ODV_QF(t1,3); % replace argo w/ ODV
                            ct =ct+1;
                        end
                    end
                    LR.([QCvars{ind,2},'_ADJUSTED_QC']) = ARGO_QF(:,3);
                    if ct > 0
                        disp([num2str(ct), ' LR QC flags added from ODV ', ...
                            'file for ', QCvars{ind,2}, '_ADJUSTED_QC'])
                    end
                    
                    % HR ADJUSTED
                    if isfield(HR,[QCvars{ind,2},'_ADJUSTED_QC'])  && ...
                            ~isempty(HR.([QCvars{ind,2},'_ADJUSTED_QC']))
                        ARGO_QF = [HR.PRES, HR.TEMP, HR.([QCvars{ind,2},'_ADJUSTED_QC'])];
                        ct = 0;
                        for i = 1:size(ARGO_QF,1) % line by line just in case
                            dP = abs(ODV_QF(:,1) - ARGO_QF(i,1));
                            dT = abs(ODV_QF(:,2) - ARGO_QF(i,2));
                            min_dP = min(dP); % this should be 0 but def < 1m
                            min_dT = min(dT);
                            if min_dP > 0.75 % poor match
                                disp(['Poor HR QF match for ARGO PRES = ', ...
                                    num2str(ARGO_QF(i,1))])
                                continue
                            end
                            t1 = dP == min_dP & dT == min_dT; % there should only be one
                            if ODV_QF(t1,3) > ARGO_QF(i,3) % ODV QF worse than ARGO
                                ARGO_QF(i,3) = ODV_QF(t1,3); % replace argo w/ ODV
                                ct =ct+1;
                            end
                        end
                        HR.([QCvars{ind,2},'_ADJUSTED_QC']) = ARGO_QF(:,3);
                        if ct > 0
                            disp([num2str(ct), ' HR QC flags added from ODV ', ....
                                'file for ', QCvars{ind,2}, '_ADJUSTED_QC'])
                        end
                    end
                end
            end
            clear tFV FVQC_cast FVQC_QF_sum indQF QF_ct ODV_QF ARGO_QF ct i
            clear dP t1 min_dP
        end
    end
    
    
    
    %-----------------------------------------------------------
    % Add LR(HR).parameter_DATA_MODE for each parameter.  12/21/17
    
    %     cycdate = d.sdn;
    cycdate = datenum(timestamps); %use date when file came in, not internal cycle date
    
    % OXYGEN
    if isfield(cal,'O')
        XEMPT_O = find(HR.DOXY ~= 99999,1); % if empty, then cycle has no data
        if isempty(QC) || isempty(XEMPT_O) % no adjustments have been made yet, or all data is 99999
            INFO.DOXY_DATA_MODE = 'R';
        elseif ~isempty(QC) && isfield(QC,'O')
            if cycdate > QC.date
                INFO.DOXY_DATA_MODE = 'A';
            else
                INFO.DOXY_DATA_MODE = 'D';
            end
        end
    end
    
    % NITRATE
    if isfield(cal,'N')
        XEMPT_N = find(LR.NITRATE ~= 99999,1); % if empty, then cycle has no data
        if isempty(QC) || isempty(XEMPT_N) % no adjustments have been made yet, or all data is 99999
            INFO.NITRATE_DATA_MODE = 'R';
        elseif ~isempty(QC) && isfield(QC,'N')
            if cycdate > QC.date
                INFO.NITRATE_DATA_MODE = 'A';
            else
                INFO.NITRATE_DATA_MODE = 'D';
            end
        end
    end
    % PH
    if isfield(cal,'pH')
        XEMPT_PH = find(HR.PH_IN_SITU_TOTAL ~= 99999,1); % if empty, then cycle has no data
        if isempty(QC) || isempty(XEMPT_PH) % no adjustments have been made yet, or all data is 99999
            INFO.PH_DATA_MODE = 'R';
        elseif ~isempty(QC) && isfield(QC,'pH')
            if cycdate > QC.date
                INFO.PH_DATA_MODE = 'A';
            else
                INFO.PH_DATA_MODE = 'D';
            end
        end
    end
    
    % BBP700
    if isfield(cal,'BB')
        if sum(LR.BBP700_ADJUSTED<99999)>0 || sum(HR.BBP700_ADJUSTED<99999)>0 % there is data for that profile --> adjustment has been made
            INFO.BBP700_DATA_MODE = 'A';
        else
            INFO.BBP700_DATA_MODE = 'R';
        end
    end
    %     if isfield(cal,'BB')
    %         INFO.BBP700_DATA_MODE = 'R';
    %     end
    % CDOM (or BBP532)
    if isfield(cal,'CDOM') && strcmp(UW_ID_str,'0565')~=1
        INFO.CDOM_DATA_MODE = 'R';
    elseif isfield(cal,'CDOM') && strcmp(UW_ID_str,'0565')==1
        if sum(LR.BBP532_ADJUSTED<99999)>0 || sum(HR.BBP532_ADJUSTED<99999)>0 % there is data for that profile --> adjustment has been made
            INFO.BBP532_DATA_MODE = 'A';
        else
            INFO.BBP532_DATA_MODE = 'R';
        end
    end
    % CHL
    if isfield(cal,'CHL')
        %         if isfield(cal.CHL,'SWDC') && isfield(cal.CHL.SWDC,'DC') % median dark count has been quantified --> adjustment has been made
        
        if sum(LR.CHLA_ADJUSTED<99999)>0 || sum(HR.CHLA_ADJUSTED<99999)>0 % there is adjusted data for that profile --> adjustment has been made
            INFO.CHLA_DATA_MODE = 'A';
        else
            INFO.CHLA_DATA_MODE = 'R';
        end
    end
    %-----------------------------------------------------------
    
    
    
    
    
    % *********************************************************************
    % SAVE THE PROFILE AS WMO_ID#.PROFILE.mat
    % THE *.mat file will contain 3 structures:
    %   LR      for low resolution data
    %   HR      for high resolution data (constant profiling)
    %   info	float info that may be of use for ARGO data stream, also
    %           used to build ODV compatible text file from *.mat files
    % *********************************************************************
    if exist('AIR_O2', 'var')
        INFO.AIR_O2   = AIR_O2; % [p t s phase cor_phase uM uMsat pO2]
    end
    
    %     WMO_chk = 0;
    %     WMO  = INFO.WMO_ID; % string
    %     if isempty(WMO) && WMO_chk == 0
    %         disp(['NO WMO# FOUND FOR FLOAT! CREATING TEMPORARY DATA DIR FOR ', ...
    %             INFO.UW_ID])
    %         WMO = ['NO_WMO_',INFO.UW_ID]; % CREATE TEMPORARY WMO NAME
    %         WMO_chk = 1;
    %     end
    
    
    save_str = [dirs.mat, WMO,'\', WMO,'.', cast_num,'.mat'];
    save(save_str,'LR','HR','INFO');
    %     if msg_ct == 1
    %         copyfile(fp_cal, [dirs.mat, WMO,'\']); % copy over cal file
    %     end
    
    
end
copyfile(fp_cal, [dirs.mat, WMO,'\']) % copy over cal file
%fprintf('\r\n')

% *********************************************************************
% CLEAN UP
if ~isempty(ls([dirs.temp,'*.msg']))
    delete([dirs.temp,'*.msg']);
end
if ~isempty(ls([dirs.temp,'*.isus']))
    delete([dirs.temp,'*.isus']);
end
if ~isempty(ls([dirs.temp,'*.dura']))
    delete([dirs.temp,'*.dura']);
end

tf_float.status = 1;
%end













