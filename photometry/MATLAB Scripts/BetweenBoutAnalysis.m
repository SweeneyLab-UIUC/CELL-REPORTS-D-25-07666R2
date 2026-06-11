%% JB 2026 Used to Analyze post consumption signal

postSec = ; % Define Seconds post consumption to analyze + Used to ensure next bout doesn't contaminate
minBoutDurSec = ; % Set if you want to control for short bouts/mislabeling

sessionNames = intersect(fieldnames(PhotometryOut), fieldnames(eventTables));

PostBoutSummary = struct();

for i = 1:numel(sessionNames)
    key = sessionNames{i};

    Te = eventTables.(key);
    P  = PhotometryOut.(key);
    t = P.Time(:);
    z = P.Z(:);

    if isempty(t) || isempty(z)
        warning('Skipping %s: missing trace.', key);
        continue
    end

    labels = string(Te{:,1});
    isEat = strcmpi(strtrim(labels), 'eating');

    if ~any(isEat)
        warning('No  eating rows found for session %s', key);
        continue
    end

    startRaw = Te{isEat, 2};
    endRaw   = Te{isEat, 3};

    eatStarts = convert_times_to_seconds(startRaw);
    eatEnds   = convert_times_to_seconds(endRaw);

    valid = isfinite(eatStarts) & isfinite(eatEnds) & (eatEnds > eatStarts);
    eatStarts = eatStarts(valid);
    eatEnds   = eatEnds(valid);

    if isempty(eatStarts)
        warning('No valid eating bouts for session %s', key);
        continue
    end

    [eatStarts, ord] = sort(eatStarts);
    eatEnds = eatEnds(ord);

    boutDur = eatEnds - eatStarts;

    keep = boutDur > minBoutDurSec;
    eatStarts = eatStarts(keep);
    eatEnds   = eatEnds(keep);
    boutDur   = boutDur(keep);

    if isempty(eatStarts)
        warning('No eating bouts > %g s for session %s', minBoutDurSec, key);
        continue
    end

    segStartAbs = P.SegmentStart_Original;
    eatStartsRel = eatStarts - segStartAbs;
    eatEndsRel   = eatEnds   - segStartAbs;


    chosenIdx = [];
    chosenMask = [];

    for j = 1:numel(eatStartsRel)
        winStart = eatEndsRel(j);
        winEnd   = eatEndsRel(j) + postSec;

        if winEnd > t(end)
            continue
        end

        laterStarts = eatStartsRel((j+1):end);
        hasNextWithinWindow = any(laterStarts < winEnd);

        if hasNextWithinWindow
            continue
        end

        mask = t >= winStart & t < winEnd;
        if nnz(mask) < 2
            continue
        end

        chosenIdx = j;
        chosenMask = mask;
        break
    end

    if isempty(chosenIdx)
        warning('No qualifying post-bout window found for session %s', key);
        PostBoutSummary.(key).Session = key;
        PostBoutSummary.(key).ChosenBoutIndex = NaN;
        PostBoutSummary.(key).PostBoutMeanZ = NaN;
        continue
    end


    meanZ = mean(z(chosenMask), 'omitnan');

    PostBoutSummary.(key).Session = key;
    PostBoutSummary.(key).ChosenBoutIndex = chosenIdx;
    PostBoutSummary.(key).ChosenBoutStart_Original = eatStarts(chosenIdx);
    PostBoutSummary.(key).ChosenBoutEnd_Original   = eatEnds(chosenIdx);
    PostBoutSummary.(key).ChosenBoutDurationSec    = boutDur(chosenIdx);

    PostBoutSummary.(key).PostWindowStart_Rel = eatEndsRel(chosenIdx);
    PostBoutSummary.(key).PostWindowEnd_Rel   = eatEndsRel(chosenIdx) + postSec;

    PostBoutSummary.(key).PostBoutMeanZ = meanZ;

    fprintf('Done: %s | chose bout %d | dur = %.2f s | post-bout mean Z = %.3f\n', ...
        key, chosenIdx, boutDur(chosenIdx), meanZ);
end

sess = fieldnames(PostBoutSummary);
Session = strings(numel(sess),1);
ChosenBoutIndex = nan(numel(sess),1);
ChosenBoutDurationSec = nan(numel(sess),1);
PostBoutMeanZ = nan(numel(sess),1);

for i = 1:numel(sess)
    S = PostBoutSummary.(sess{i});
    Session(i) = string(S.Session);
    ChosenBoutIndex(i) = S.ChosenBoutIndex;
    if isfield(S,'ChosenBoutDurationSec')
        ChosenBoutDurationSec(i) = S.ChosenBoutDurationSec;
    end
    if isfield(S,'PostBoutMeanZ')
        PostBoutMeanZ(i) = S.PostBoutMeanZ;
    end
end

PostBoutTable = table(Session, ChosenBoutIndex, ChosenBoutDurationSec, PostBoutMeanZ);
disp(PostBoutTable);

%% ---------------- helper ----------------
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
        % leave as is
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