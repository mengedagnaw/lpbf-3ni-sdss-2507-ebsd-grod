%% MTEX_GROD_TSL_OIM_SDSS.m
% Grain Reference Orientation Deviation (GROD) analysis for EDAX/TSL OIM *.ang EBSD files.
%
% Dataset context:
%   Designed for LPBF / heat-treated duplex stainless steel EBSD maps exported
%   from EDAX/TSL OIM as *.ang files, e.g. AS, SR400, SR450, SR500, SR550,
%   SA1100. The script is phase-aware and works with ferrite + austenite maps.
%
% Main outputs:
%   1) MTEX-ready *.mat files after explicit TSL/OIM reference-frame conversion.
%   2) IPF maps with grain boundaries.
%   3) Phase maps with grain boundaries.
%   4) GROD / misorientation-to-grain-mean angle maps in degrees.
%   5) Grain orientation spread (GOS) maps in degrees.
%   6) Pixel GROD histograms and CDFs.
%   7) Grain GOS histograms.
%   8) Summary CSV containing mean, median, std, P75, P90, P95, P99, min, max,
%      and fraction above 1 degree.
%   9) Optional phase-specific maps/statistics.
%  10) Optional GROD-axis maps.
%
% Critical convention note:
%   EDAX/TSL OIM *.ang files are MTEX-compatible, but they should not be treated
%   as fully MTEX-ready until the Euler and spatial reference-frame convention is
%   explicitly fixed during import. This script uses the common TSL/OIM correction:
%
%       'convertEuler2SpatialReferenceFrame','setting 2'
%
%   Verify this once against your OIM-exported IPF/phase maps and then use the
%   same import convention for every dataset in the study.
%
% Important interpretation note:
%   The scalar map labelled "misorientation angle to grain mean orientation" is
%   the GROD angle in degrees:
%
%       grodDeg = grod.angle ./ degree
%
%   This is the pixel-wise misorientation between each EBSD pixel orientation and
%   the mean/reference orientation of the grain to which that pixel belongs.
%   It is commonly used as a qualitative proxy for intragranular orientation
%   gradients, local lattice curvature, and deformation heterogeneity. It is not
%   a direct dislocation-density measurement unless combined with additional
%   assumptions and spatial-gradient analysis.

clear; close all; clc;

%% ======================== MTEX STARTUP CHECK ============================
% Put your MTEX installation folder here if MATLAB cannot find startup_mtex.
% Leave it empty if MTEX is already on the MATLAB path.
%
% Examples:
%   mtexRoot = '/MATLAB Drive/mtex';
%   mtexRoot = '/MATLAB Drive/mtex-6.1.0';
%   mtexRoot = 'C:/Users/YourName/Documents/MATLAB/mtex';
%
% Your screenshot shows mtex-6.1.0 inside the same folder as this script.
% The following auto-detects that common layout.
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end

mtexRoot = fullfile(scriptDir, 'mtex-6.1.0');

% If your MTEX folder is somewhere else, override the line above manually, e.g.:
% mtexRoot = '/MATLAB Drive/SDSS 2507_EBSD/mtex-6.1.0';

if ~isempty(mtexRoot)
    if exist(mtexRoot, 'dir') ~= 7
        error('The specified mtexRoot folder does not exist: %s', mtexRoot);
    end
    % Add only the MTEX root folder. startup_mtex will add the required MTEX
    % subfolders in the correct order. Using genpath directly can introduce
    % compatibility functions that shadow MATLAB built-ins such as contains/isgraphics.
    addpath(mtexRoot);
end

% The MTEX examples use the angle constant "degree". If MATLAB reports
% "Unrecognized function or variable 'degree'", MTEX has usually not been
% initialized in the current session.
if exist('startup_mtex', 'file') == 2
    try
        startup_mtex;
    catch ME
        warning('startup_mtex was found but did not complete cleanly: %s', ME.message);
    end
end

if ~(exist('EBSD', 'class') == 8 || exist('EBSD', 'file') == 2)
    error(['MTEX is not available on the MATLAB path. Install MTEX and run startup_mtex, ', ...
           'or add the MTEX folder to the MATLAB path before running this script.']);
end

if ~exist('degree', 'var')
    degree = pi/180;
    warning('MTEX variable "degree" was unavailable. Using degree = pi/180 as a numerical fallback.');
end

%% ============================ USER SETTINGS =============================
% Select the extracted folder that contains AS_500x500.ang, SR400_500x500.ang, etc.
dataRoot = uigetdir(pwd, 'Select folder containing the extracted *.ang files');
if isequal(dataRoot,0)
    error('No folder selected. Extract the .zip archive first and select the root folder.');
end

outRoot = fullfile(dataRoot, 'MTEX_GROD_results');
if ~exist(outRoot, 'dir'); mkdir(outRoot); end

% EDAX/TSL OIM import convention.
% Recommended first choice for OIM .ang:
%   keep x-y map coordinates and convert Euler angles into the spatial/map frame.
importConversion = 'convertEuler2SpatialReferenceFrame';
edaxSetting      = 'setting 2';

% Display-only convention. This changes how maps are drawn, not the EBSD data.
% Use this to obtain an OIM-like map orientation on screen/exported images.
applyOIMLikeScreenConvention = true;

% Grain reconstruction.
% For duplex stainless steel, keep this defensible and report it in the methods.
subgrainAngle = 1.0 * degree;      % low-angle/inner-boundary visualization threshold
grainAngle    = 10.0 * degree;     % grain-defining threshold
minPixel      = 5;                 % remove tiny grains/noise islands

% Orientation denoising.
% Denoising changes quantitative GROD values; use the same setting for all samples.
doDenoise       = true;
filterAlpha     = 0.5;
grainSmoothIter = 5;

% Plot/statistics settings.
grodCaxisMax_deg = 5;              % fixed color range for cross-sample comparison
histBinWidth_deg = 0.05;
doPhaseSpecificStats = true;
doAxisMaps           = false;      % set true for GROD-axis maps; slower
makeConventionCheck  = true;       % preview import conventions for the first file

% Export settings.
exportResolution = 300;

%% ============================ FIND ANG FILES ============================
angFiles = localFindFiles(dataRoot, '.ang');
if isempty(angFiles)
    error('No .ang files were found under: %s', dataRoot);
end
fprintf('Found %d ANG file(s).\n', numel(angFiles));

%% ================== OPTIONAL IMPORT-CONVENTION CHECK ====================
if makeConventionCheck
    fprintf('\nCreating import-convention check maps for:\n  %s\n', angFiles{1});
    localConventionCheck(angFiles{1}, outRoot, edaxSetting, applyOIMLikeScreenConvention, exportResolution);
end

%% ============================ MAIN ANALYSIS =============================
allStats = table();

settings = struct();
settings.importConversion = importConversion;
settings.edaxSetting = edaxSetting;
settings.applyOIMLikeScreenConvention = applyOIMLikeScreenConvention;
settings.subgrainAngle_deg = subgrainAngle / degree;
settings.grainAngle_deg = grainAngle / degree;
settings.minPixel = minPixel;
settings.doDenoise = doDenoise;
settings.filterAlpha = filterAlpha;
settings.grainSmoothIter = grainSmoothIter;
settings.grodCaxisMax_deg = grodCaxisMax_deg;
settings.histBinWidth_deg = histBinWidth_deg;

for k = 1:numel(angFiles)
    fileName = angFiles{k};
    [~, sampleName] = fileparts(fileName);
    sampleName = regexprep(sampleName, '_500x500$', '');
    sampleTag = localSafeName(sampleName);

    fprintf('\n[%d/%d] Processing %s\n', k, numel(angFiles), sampleName);
    sampleOut = fullfile(outRoot, sampleTag);
    if ~exist(sampleOut, 'dir'); mkdir(sampleOut); end

    %% ---- Import with explicit TSL/OIM reference-frame conversion ----
    ebsd = EBSD.load(fileName, 'interface', 'ang', importConversion, edaxSetting);

    if applyOIMLikeScreenConvention
        ebsd.how2plot.east = xvector;
        ebsd.how2plot.outOfScreen = -zvector;
    end

    % Restrict to indexed pixels.
    ebsd = ebsd('indexed');

    % MTEX can exploit gridded EBSD data for filtering and plotting.
    try
        ebsd = ebsd.gridify;
    catch ME
        warning('gridify failed for %s. Continuing with ungridded EBSD. Reason: %s', sampleName, ME.message);
    end

    %% ---- Grain reconstruction ----
    % ebsd.mis2mean from calcGrains is the native MTEX misorientation-to-mean
    % quantity. After denoising below, the script recomputes the GROD object and
    % uses grod.angle./degree for the final plotted scalar maps/statistics.
    [grains, ebsd.grainId, ebsd.mis2mean] = calcGrains(ebsd, ...
        'threshold', [subgrainAngle, grainAngle], 'minPixel', minPixel);
    grains = smooth(grains, grainSmoothIter);

    %% ---- Optional denoising, preserving phase/grain topology ----
    ebsdForGROD = ebsd;
    if doDenoise
        F = halfQuadraticFilter;
        F.alpha = filterAlpha;
        ebsdForGROD = smooth(ebsd, F, grains, 'fill');
        ebsdForGROD.grainId = ebsd.grainId;
    end

    %% ---- GROD: pixel misorientation to grain mean orientation ----
    grod = ebsdForGROD.calcGROD(grains);

    % This is the requested map quantity:
    % pixel-wise misorientation angle to grain mean/reference orientation, degrees.
    mis2meanDeg = grod.angle ./ degree;

    % Grain orientation spread: grain-average of the pixel GROD angle.
    GOSdeg = grainMean(ebsdForGROD, grod.angle, grains) ./ degree;

    %% ---- Save MTEX-ready object after reference-frame correction ----
    ebsdMTEX = ebsdForGROD; %#ok<NASGU>
    save(fullfile(sampleOut, [sampleTag '_MTEX_ready_' importConversion '_' regexprep(edaxSetting,'\s+','') '.mat']), ...
        'ebsdMTEX', 'grains', 'grod', 'mis2meanDeg', 'GOSdeg', 'settings', '-v7.3');

    %% ---- Maps ----
    localPlotIPFMap(ebsdForGROD, grains, sampleName, sampleOut, exportResolution);
    localPlotPhaseMap(ebsdForGROD, grains, sampleName, sampleOut, exportResolution);

    % Requested degree map: misorientation angle to grain mean orientation.
    localPlotMis2MeanMap(ebsdForGROD, grains, mis2meanDeg, grodCaxisMax_deg, sampleName, sampleOut, exportResolution);

    % GOS map: grain-level average of the same misorientation-angle field.
    localPlotGOSMap(grains, GOSdeg, grodCaxisMax_deg, sampleName, sampleOut, exportResolution);

    %% ---- Histograms and CDFs ----
    localPlotHistogram(mis2meanDeg, histBinWidth_deg, ...
        sprintf('%s - pixel misorientation angle to grain mean orientation', sampleName), ...
        'Misorientation angle to grain mean orientation (degree)', ...
        fullfile(sampleOut, [sampleTag '_hist_pixel_mis2mean_angle_deg.png']), exportResolution);

    localPlotCDF(mis2meanDeg, ...
        sprintf('%s - pixel misorientation angle to grain mean orientation CDF', sampleName), ...
        'Misorientation angle to grain mean orientation (degree)', ...
        fullfile(sampleOut, [sampleTag '_cdf_pixel_mis2mean_angle_deg.png']), exportResolution);

    localPlotHistogram(GOSdeg, histBinWidth_deg, ...
        sprintf('%s - grain GOS', sampleName), ...
        'GOS (degree)', ...
        fullfile(sampleOut, [sampleTag '_hist_grain_GOS_deg.png']), exportResolution);

    %% ---- Summary statistics: all indexed pixels/grains ----
    allStats = [allStats; localStatsTable(sampleName, 'ALL_INDEXED_PHASES', ...
        'Pixel_misorientation_to_grain_mean_angle_deg', mis2meanDeg)]; %#ok<AGROW>

    allStats = [allStats; localStatsTable(sampleName, 'ALL_INDEXED_PHASES', ...
        'Grain_GOS_deg', GOSdeg)]; %#ok<AGROW>

    %% ---- Phase-specific GROD/GOS statistics from the full-map GROD field ----
    % Robust strategy for duplex EBSD:
    %   1) reconstruct grains once on the indexed full map;
    %   2) calculate GROD once from that full-map grain topology;
    %   3) extract ferrite/austenite statistics from the scalar GROD field.
    % This avoids fragile phase-specific re-calcGrains/re-calcGROD operations on
    % gridded phase subsets, which can trigger MTEX grainId/subSet errors.
    if doPhaseSpecificStats
        phaseIds = unique(ebsdForGROD.phaseId(:));
        phaseIds = phaseIds(isfinite(phaseIds) & phaseIds > 0);
        phaseIds = phaseIds(:).';

        for pid = phaseIds
            phaseMask = ebsdForGROD.phaseId == pid;

            if nnz(phaseMask) < max(20, 3*minPixel)
                continue;
            end

            try
                ebsdP = ebsdForGROD(phaseMask);
            catch ME
                warning('Skipping phaseId %g in %s because EBSD phase selection failed: %s', pid, sampleName, ME.message);
                continue;
            end

            if length(ebsdP) < max(20, 3*minPixel)
                continue;
            end

            phaseName = localPhaseName(ebsdP, pid);
            phaseTag  = localSafeName(sprintf('phase_%g_%s', pid, phaseName));
            phaseOut  = fullfile(sampleOut, phaseTag);
            if ~exist(phaseOut, 'dir'); mkdir(phaseOut); end

            mis2meanPDeg = mis2meanDeg(phaseMask);
            mis2meanPDeg = mis2meanPDeg(isfinite(mis2meanPDeg));

            % Phase-specific grain list from the full-map grain topology.
            % GOSdeg is aligned with grains, while grains.id stores the EBSD grain IDs.
            try
                phaseGrainIds = unique(ebsdForGROD.grainId(phaseMask));
                phaseGrainIds = phaseGrainIds(isfinite(phaseGrainIds) & phaseGrainIds > 0);
                grIdx = ismember(grains.id, phaseGrainIds);
                GOSPdeg = GOSdeg(grIdx);
                GOSPdeg = GOSPdeg(isfinite(GOSPdeg));
            catch ME
                warning('Could not extract phase-specific GOS for %s / phaseId %g: %s', sampleName, pid, ME.message);
                GOSPdeg = [];
            end

            % Phase-specific scalar map. Boundaries are deliberately omitted here
            % to avoid MTEX grain-subset instability; use the full-map GROD map for
            % boundary-overlaid visualization.
            try
                fig = figure('Color','w', 'Name', sprintf('%s - %s - phase GROD angle', sampleName, phaseName));
                plot(ebsdP, mis2meanPDeg, 'micronbar', 'on');
                mtexColorMap LaboTeX;
                mtexColorbar('title', 'Misorientation to grain mean (degree)');
                if ~isempty(grodCaxisMax_deg) && isfinite(grodCaxisMax_deg) && grodCaxisMax_deg > 0
                    setColorRange([0 grodCaxisMax_deg]);
                end
                title(sprintf('%s - %s - misorientation angle to grain mean orientation', ...
                    strrep(sampleName,'_','\_'), strrep(phaseName,'_','\_')));
                localSaveFig(fig, fullfile(phaseOut, [sampleTag '_' phaseTag '_misorientation_to_grain_mean_angle_deg_map.png']), exportResolution);
                close(fig);
            catch ME
                warning('Phase-specific GROD angle map failed for %s / %s: %s', sampleName, phaseName, ME.message);
            end

            localPlotHistogram(mis2meanPDeg, histBinWidth_deg, ...
                sprintf('%s - %s - pixel misorientation angle to grain mean orientation', sampleName, phaseName), ...
                'Misorientation angle to grain mean orientation (degree)', ...
                fullfile(phaseOut, [sampleTag '_' phaseTag '_hist_pixel_mis2mean_angle_deg.png']), exportResolution);

            localPlotCDF(mis2meanPDeg, ...
                sprintf('%s - %s - pixel misorientation angle to grain mean orientation CDF', sampleName, phaseName), ...
                'Misorientation angle to grain mean orientation (degree)', ...
                fullfile(phaseOut, [sampleTag '_' phaseTag '_cdf_pixel_mis2mean_angle_deg.png']), exportResolution);

            localPlotHistogram(GOSPdeg, histBinWidth_deg, ...
                sprintf('%s - %s - grain GOS', sampleName, phaseName), ...
                'GOS (degree)', ...
                fullfile(phaseOut, [sampleTag '_' phaseTag '_hist_grain_GOS_deg.png']), exportResolution);

            allStats = [allStats; localStatsTable(sampleName, phaseName, ...
                'Pixel_misorientation_to_grain_mean_angle_deg', mis2meanPDeg)]; %#ok<AGROW>

            allStats = [allStats; localStatsTable(sampleName, phaseName, ...
                'Grain_GOS_deg', GOSPdeg)]; %#ok<AGROW>
        end
    end
end

%% ================= SAVE SUMMARY TABLE AND COMPARISON PLOTS ==============
statsFile = fullfile(outRoot, 'GROD_GOS_summary_statistics.csv');
writetable(allStats, statsFile);
fprintf('\nSaved summary statistics:\n  %s\n', statsFile);

localPlotSummaryBars(allStats, outRoot, exportResolution);
save(fullfile(outRoot, 'GROD_all_summary_workspace.mat'), 'allStats', 'settings', '-v7.3');

disp(allStats);
fprintf('\nDone. Results folder:\n  %s\n', outRoot);

%% ========================================================================
%% LOCAL FUNCTIONS
%% ========================================================================
function files = localFindFiles(rootDir, ext)
    d = dir(fullfile(rootDir, '**', ['*' ext]));
    if isempty(d)
        parts = regexp(genpath(rootDir), pathsep, 'split');
        d = [];
        for i = 1:numel(parts)
            if isempty(parts{i}); continue; end
            di = dir(fullfile(parts{i}, ['*' ext]));
            d = [d; di]; %#ok<AGROW>
        end
    end
    files = arrayfun(@(s) fullfile(s.folder, s.name), d, 'UniformOutput', false);
    files = sort(files(:));
end

function s = localSafeName(s)
    s = char(s);
    s = regexprep(s, '[^A-Za-z0-9]+', '_');
    s = regexprep(s, '^_+|_+$', '');
    if isempty(s); s = 'unnamed'; end
end

function phaseName = localPhaseName(ebsdP, pid)
    phaseName = sprintf('phase_%d', pid);
    try
        phaseName = char(ebsdP.CS.mineral);
        if isempty(phaseName)
            phaseName = sprintf('phase_%d', pid);
        end
    catch
        phaseName = sprintf('phase_%d', pid);
    end
end

function localConventionCheck(fileName, outRoot, edaxSetting, applyScreenConvention, exportResolution)
    [~, sampleName] = fileparts(fileName);
    sampleTag = localSafeName(regexprep(sampleName, '_500x500$', ''));
    outDir = fullfile(outRoot, '00_import_convention_check');
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    labels = {'raw_no_conversion', 'Euler2Spatial_setting2', 'Spatial2Euler_setting2'};
    args = { {}, {'convertEuler2SpatialReferenceFrame', edaxSetting}, {'convertSpatial2EulerReferenceFrame', edaxSetting} };

    for i = 1:numel(labels)
        ebsd = EBSD.load(fileName, 'interface', 'ang', args{i}{:});
        ebsd = ebsd('indexed');

        if applyScreenConvention
            ebsd.how2plot.east = xvector;
            ebsd.how2plot.outOfScreen = -zvector;
        end

        try
            ebsd = ebsd.gridify;
        catch
        end

        % Duplex data contain ferrite and austenite. MTEX does not allow a direct
        % orientation-color plot of a multi-phase EBSD object because each phase
        % has its own crystal symmetry. Plot the convention-check IPF map phase by
        % phase instead.
        localPlotIPFMap(ebsd, [], sprintf('%s | %s', sampleName, labels{i}), outDir, exportResolution, ...
            [sampleTag '_' labels{i} '_IPF_check.png']);

        fig = figure('Color','w', 'Name', [sampleName ' - phase - ' labels{i}]);
        plot(ebsd, 'coordinates', 'on', 'micronbar', 'on');
        title(sprintf('%s | phase map | %s', strrep(sampleName,'_','\_'), strrep(labels{i},'_','\_')));
        localSaveFig(fig, fullfile(outDir, [sampleTag '_' labels{i} '_phase_check.png']), exportResolution);
        close(fig);
    end
end

function localPlotIPFMap(ebsd, grains, sampleName, outDir, exportResolution, optionalFileName)
    if nargin < 6 || isempty(optionalFileName)
        optionalFileName = [localSafeName(sampleName) '_IPF_grain_boundaries.png'];
    end

    fig = figure('Color','w', 'Name', [sampleName ' - phase-resolved IPF map']);
    hold on;

    % Use mineral names rather than phaseId indexing. This is more robust for
    % EDAX/TSL ANG files because MTEX may carry a notIndexed entry and because
    % orientation-color plotting is only valid for a single crystal symmetry at a time.
    mineralList = ebsd.mineralList;
    firstPhase = true;

    for ii = 1:numel(mineralList)
        mineralName = mineralList{ii};
        if contains(lower(mineralName), 'notindexed') || contains(lower(mineralName), 'not indexed')
            continue;
        end

        try
            ebsdP = ebsd(mineralName);
        catch
            continue;
        end

        if isempty(ebsdP)
            continue;
        end

        % Extra guard: if MTEX still reports more than one phase, skip this phase
        % rather than stopping the full GROD workflow.
        try
            if numel(unique(ebsdP.phaseId)) > 1
                warning('Skipping IPF plot for %s because selection is not single-phase.', mineralName);
                continue;
            end
        catch
        end

        if firstPhase
            plot(ebsdP, ebsdP.orientations, 'micronbar', 'on');
            firstPhase = false;
        else
            plot(ebsdP, ebsdP.orientations, 'micronbar', 'off');
        end
    end

    if ~isempty(grains)
        plot(grains.boundary, 'lineWidth', 1.0);
    end

    hold off;
    title([strrep(sampleName,'_','\_') ' - phase-resolved IPF map']);
    localSaveFig(fig, fullfile(outDir, optionalFileName), exportResolution);
    close(fig);
end

function localPlotPhaseMap(ebsd, grains, sampleName, outDir, exportResolution)
    fig = figure('Color','w', 'Name', [sampleName ' - phase map']);
    plot(ebsd, 'micronbar', 'on');
    hold on;
    plot(grains.boundary, 'lineWidth', 1.0);
    hold off;
    title([strrep(sampleName,'_','\_') ' - phase map + grain boundaries']);
    localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_phase_grain_boundaries.png']), exportResolution);
    close(fig);
end

function localPlotMis2MeanMap(ebsd, grains, mis2meanDeg, cmax, sampleName, outDir, exportResolution)
    % This is the main requested degree map:
    % each pixel color = misorientation angle between that pixel and the grain mean orientation.
    fig = figure('Color','w', 'Name', [sampleName ' - misorientation to grain mean angle map']);
    plot(ebsd, mis2meanDeg, 'micronbar', 'on');
    mtexColorMap LaboTeX;
    mtexColorbar('title', 'Misorientation to grain mean (degree)');

    if ~isempty(cmax) && isfinite(cmax) && cmax > 0
        setColorRange([0 cmax]);
    end

    hold on;
    plot(grains.boundary, 'lineWidth', 1.0);

    % Optional visualization of inner/subgrain boundaries, if available.
    try
        alphaVal = min(grains.innerBoundary.misorientation.angle ./ (5*localDegree()), 1);
        plot(grains.innerBoundary, 'edgeAlpha', alphaVal);
    catch
    end
    hold off;

    title([strrep(sampleName,'_','\_') ' - misorientation angle to grain mean orientation']);
    localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_misorientation_to_grain_mean_angle_deg_map.png']), exportResolution);
    close(fig);
end

function localPlotGOSMap(grains, GOSdeg, cmax, sampleName, outDir, exportResolution)
    fig = figure('Color','w', 'Name', [sampleName ' - GOS map']);
    plot(grains, GOSdeg);
    mtexColorMap LaboTeX;
    mtexColorbar('title', 'GOS (degree)');

    if ~isempty(cmax) && isfinite(cmax) && cmax > 0
        setColorRange([0 cmax]);
    end

    title([strrep(sampleName,'_','\_') ' - grain orientation spread']);
    localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_GOS_deg_map.png']), exportResolution);
    close(fig);
end

function localPlotHistogram(x, binWidth, ttl, xlab, outFile, exportResolution)
    x = x(:);
    x = x(isfinite(x));
    if isempty(x); return; end

    fig = figure('Color','w', 'Name', ttl);
    histogram(x, 'BinWidth', binWidth, 'Normalization', 'probability');
    xlabel(xlab);
    ylabel('Probability');
    title(strrep(ttl,'_','\_'));
    grid on;
    localSaveFig(fig, outFile, exportResolution);
    close(fig);
end

function localPlotCDF(x, ttl, xlab, outFile, exportResolution)
    x = x(:);
    x = sort(x(isfinite(x)));
    if isempty(x); return; end

    y = (1:numel(x)).' ./ numel(x);

    fig = figure('Color','w', 'Name', ttl);
    plot(x, y, 'LineWidth', 1.5);
    xlabel(xlab);
    ylabel('Cumulative probability');
    title(strrep(ttl,'_','\_'));
    grid on;
    localSaveFig(fig, outFile, exportResolution);
    close(fig);
end

function localPlotGRODAxisMaps(ebsdP, grainsP, grodP, sampleName, phaseName, outDir, exportResolution)
    phaseTag = localSafeName(phaseName);

    % Crystal-coordinate GROD axis map.
    try
        axCrystal = grodP.axis;
        colorKeyC = HSVDirectionKey(ebsdP.CS, 'antipodal');
        rgbC = colorKeyC.direction2color(axCrystal);
        alphaC = min((grodP.angle ./ localDegree()) ./ 7.5, 1);

        fig = figure('Color','w', 'Name', [sampleName ' - ' phaseName ' - GROD crystal axis']);
        plot(ebsdP, rgbC, 'micronbar', 'on', 'faceAlpha', alphaC);
        hold on;
        plot(grainsP.boundary, 'lineWidth', 1.0);
        hold off;
        title(sprintf('%s - %s - GROD axis, crystal coordinates', ...
            strrep(sampleName,'_','\_'), strrep(phaseName,'_','\_')));
        localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_' phaseTag '_GROD_axis_crystal_map.png']), exportResolution);
        close(fig);

        fig = figure('Color','w', 'Name', [sampleName ' - ' phaseName ' - crystal axis distribution']);
        plot(axCrystal, 'contourf', 'fundamentalRegion', 'antipodal');
        mtexColorbar('title', 'mrd');
        title(sprintf('%s - %s - GROD axis distribution, crystal coordinates', ...
            strrep(sampleName,'_','\_'), strrep(phaseName,'_','\_')));
        localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_' phaseTag '_GROD_axis_crystal_distribution.png']), exportResolution);
        close(fig);
    catch ME
        warning('Crystal-axis GROD plot failed for %s / %s: %s', sampleName, phaseName, ME.message);
    end

    % Specimen-coordinate GROD axis map.
    try
        axSpecimen = ebsdP.orientations .* grodP.axis('noSymmetry');
        colorKeyS = HSVDirectionKey;
        rgbS = colorKeyS.direction2color(axSpecimen);
        alphaS = min((grodP.angle ./ localDegree()) ./ 7.5, 1);

        fig = figure('Color','w', 'Name', [sampleName ' - ' phaseName ' - GROD specimen axis']);
        plot(ebsdP, rgbS, 'micronbar', 'on', 'faceAlpha', alphaS);
        hold on;
        plot(grainsP.boundary, 'lineWidth', 1.0);
        hold off;
        title(sprintf('%s - %s - GROD axis, specimen coordinates', ...
            strrep(sampleName,'_','\_'), strrep(phaseName,'_','\_')));
        localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_' phaseTag '_GROD_axis_specimen_map.png']), exportResolution);
        close(fig);

        fig = figure('Color','w', 'Name', [sampleName ' - ' phaseName ' - specimen axis distribution']);
        plot(axSpecimen, 'contourf', 'antipodal', 'halfwidth', 2.5*localDegree());
        mtexColorbar('title', 'mrd');
        title(sprintf('%s - %s - GROD axis distribution, specimen coordinates', ...
            strrep(sampleName,'_','\_'), strrep(phaseName,'_','\_')));
        localSaveFig(fig, fullfile(outDir, [localSafeName(sampleName) '_' phaseTag '_GROD_axis_specimen_distribution.png']), exportResolution);
        close(fig);
    catch ME
        warning('Specimen-axis GROD plot failed for %s / %s: %s', sampleName, phaseName, ME.message);
    end
end

function T = localStatsTable(sampleName, phaseName, metricName, x)
    x = x(:);
    x = x(isfinite(x));

    if isempty(x)
        n = 0;
        vals = nan(1,10);
    else
        n = numel(x);
        vals = [mean(x), std(x), median(x), localPercentile(x, 75), ...
                localPercentile(x, 90), localPercentile(x, 95), localPercentile(x, 99), ...
                min(x), max(x), sum(x > 1.0) / n];
    end

    T = table(string(sampleName), string(phaseName), string(metricName), n, ...
        vals(1), vals(2), vals(3), vals(4), vals(5), vals(6), vals(7), vals(8), vals(9), vals(10), ...
        'VariableNames', {'Sample','Phase','Metric','N','Mean','Std','Median','P75','P90','P95','P99','Min','Max','FractionAbove1deg'});
end

function pval = localPercentile(x, p)
    x = sort(x(:));
    x = x(isfinite(x));

    if isempty(x)
        pval = NaN;
        return;
    end

    if numel(x) == 1
        pval = x;
        return;
    end

    q = 1 + (numel(x)-1) * p / 100;
    lo = floor(q);
    hi = ceil(q);

    if lo == hi
        pval = x(lo);
    else
        pval = x(lo) + (q-lo) * (x(hi)-x(lo));
    end
end

function localPlotSummaryBars(allStats, outRoot, exportResolution)
    if isempty(allStats); return; end

    idx = allStats.Phase == "ALL_INDEXED_PHASES" & ...
          allStats.Metric == "Pixel_misorientation_to_grain_mean_angle_deg";
    T = allStats(idx,:);

    if ~isempty(T)
        fig = figure('Color','w', 'Name', 'Misorientation-to-mean summary: median and P95');
        x = categorical(T.Sample);
        x = reordercats(x, cellstr(T.Sample));
        bar(x, [T.Median, T.P95]);
        ylabel('Misorientation angle to grain mean orientation (degree)');
        legend({'Median','P95'}, 'Location', 'best');
        title('Pixel misorientation-to-grain-mean angle comparison across samples');
        grid on;
        localSaveFig(fig, fullfile(outRoot, 'misorientation_to_grain_mean_summary_median_P95_all_samples.png'), exportResolution);
        close(fig);
    end

    idx2 = allStats.Phase == "ALL_INDEXED_PHASES" & allStats.Metric == "Grain_GOS_deg";
    T2 = allStats(idx2,:);

    if ~isempty(T2)
        fig = figure('Color','w', 'Name', 'GOS summary: median and P95');
        x2 = categorical(T2.Sample);
        x2 = reordercats(x2, cellstr(T2.Sample));
        bar(x2, [T2.Median, T2.P95]);
        ylabel('GOS (degree)');
        legend({'Median','P95'}, 'Location', 'best');
        title('Grain orientation spread comparison across samples');
        grid on;
        localSaveFig(fig, fullfile(outRoot, 'GOS_summary_median_P95_all_samples.png'), exportResolution);
        close(fig);
    end
end

function localSaveFig(fig, outFile, exportResolution)
    drawnow;
    try
        exportgraphics(fig, outFile, 'Resolution', exportResolution);
    catch
        print(fig, outFile, '-dpng', ['-r' num2str(exportResolution)]);
    end
end

function d = localDegree()
    % Local functions do not inherit variables from the script workspace.
    % MTEX angle values are in radians, so pi/180 is the correct numerical
    % conversion factor for degrees.
    d = pi/180;
end
