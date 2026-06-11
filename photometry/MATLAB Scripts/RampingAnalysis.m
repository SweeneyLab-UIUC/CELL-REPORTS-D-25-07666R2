%%% JB 2026 Used for Ramping of DA Signal Prior to Initial Bout
% =========================================================

preBoutSec     = 20; % Time Prior to first bout to analyze
baselineStart  = -20; %Start of baseline relative to bout start
baselineEnd    = -10; %End of baseline relative to bout start
avgStart       = -10; %Start of averaging relative to bout start
avgEnd         = 0; %End of averaging relative to bout start
minBoutDurSec  = 0; %Controls if you want to skip mislabeled/extremely short bouts

sessionNames = intersect(fieldnames(eventTables), fieldnames(dffTables));
RampingOut = struct();

for i = 1:numel(sessionNames)
    key = sessionNames{i};

    Te = eventTables.(key);
    Td = dffTables.(key);

    t = Td.Time(:);
    y = Td.dFF(:);

    good = isfinite(t) & isfinite(y);
    t = t(good);
    y = y(good);

    if numel(t) < 2
        warning('Skipping %s: trace too short.', key);
        continue
    end
    labels = string(Te{:,1});
    labels = strtrim(labels);

    isEat = strcmpi(labels, 'RC eating') | strcmpi(labels, 'eating');

    if ~any(isEat)
        warning('No eating rows found for session %s', key);
        continue
    end

    startRaw = Te{isEat, 2};
    endRaw   = Te{isEat, 3};

    eatStarts = convert_times_to_seconds(startRaw);
    eatEnds   = convert_times_to_seconds(endRaw);

    validBout = isfinite(eatStarts) & isfinite(eatEnds) & (eatEnds > eatStarts);
    eatStarts = eatStarts(validBout);
    eatEnds   = eatEnds(validBout);

    if isempty(eatStarts)
        warning('No valid eating bouts found for session %s', key);
        continue
    end

    [eatStarts, sortIdx] = sort(eatStarts);
    eatEnds = eatEnds(sortIdx);

    boutDur = eatEnds - eatStarts;

    keep = boutDur >= minBoutDurSec;

    if ~any(keep)
        warning('No eating bouts >= %g s for session %s', minBoutDurSec, key);
        continue
    end

    firstIdx = find(keep, 1, 'first');

    boutStart = eatStarts(firstIdx);
    boutEnd   = eatEnds(firstIdx);
    boutDur   = boutDur(firstIdx);

    winStart = boutStart - preBoutSec;
    winEnd   = boutStart;

    if winStart < t(1)
        warning('%s: less than 20 s pre-bout available. Skipping.', key);
        continue
    end

    winMask = t >= winStart & t < winEnd;

    tWin = t(winMask);
    yWin = y(winMask);

    if isempty(tWin)
        warning('No retained pre-bout samples for session %s', key);
        continue
    end
    tRel = tWin - boutStart;

    baselineMask = tRel >= baselineStart & tRel < baselineEnd;

    if sum(baselineMask) < 5
        warning('%s: too few baseline points from -20 to -10 s. Skipping.', key);
        continue
    end

    mu = mean(yWin(baselineMask), 'omitnan');
    sd = std(yWin(baselineMask), 0, 'omitnan');

    if ~isfinite(sd) || sd == 0
        warning('%s: baseline std invalid. Skipping.', key);
        continue
    end

    zWin = (yWin - mu) ./ sd;


    avgMask = tRel >= avgStart & tRel < avgEnd;

    meanPreBoutZ = mean(zWin(avgMask), 'omitnan');
    meanPreBoutRaw = mean(yWin(avgMask), 'omitnan');


    RampingOut.(key).Session = key;

    RampingOut.(key).TimeRelativeToBout = tRel;
    RampingOut.(key).dFF_PreBout = yWin;
    RampingOut.(key).Z_PreBout = zWin;

    RampingOut.(key).BaselineMean = mu;
    RampingOut.(key).BaselineStd = sd;

    RampingOut.(key).MeanZ_minus10_to_0 = meanPreBoutZ;
    RampingOut.(key).MeanRaw_minus10_to_0 = meanPreBoutRaw;

    RampingOut.(key).QualifyingBoutStart_Original = boutStart;
    RampingOut.(key).QualifyingBoutEnd_Original = boutEnd;
    RampingOut.(key).QualifyingBoutDurationSec = boutDur;
    RampingOut.(key).QualifyingBoutIndex = firstIdx;

    fprintf('Done: %s | bout %.2f s | dur %.2f s | mean Z -10:0 = %.3f\n', ...
        key, boutStart, boutDur, meanPreBoutZ);
end


function sec = convert_times_to_seconds(x)

    if isnumeric(x)
        sec = double(x);
        return
    end

    if iscell(x)
        x = string(x);
    elseif ischar(x)
        x = string(x);
    elseif isstring(x)
    else
        try
            sec = seconds(x);
            return
        catch
            sec = nan(size(x));
            return
        end
    end

    sec = nan(size(x));

    for ii = 1:numel(x)
        xi = strtrim(x(ii));

        if strlength(xi) == 0 || ismissing(xi)
            continue
        end

        try
            sec(ii) = seconds(duration(xi,'InputFormat','hh:mm:ss.SSS'));
            continue
        catch
        end

        try
            sec(ii) = seconds(duration(xi,'InputFormat','hh:mm:ss'));
            continue
        catch
        end

        try
            sec(ii) = seconds(duration(xi,'InputFormat','mm:ss.SSS'));
            continue
        catch
        end

        try
            sec(ii) = seconds(duration(xi,'InputFormat','mm:ss'));
            continue
        catch
        end

        v = str2double(xi);
        if isfinite(v)
            sec(ii) = v;
        end
    end
end