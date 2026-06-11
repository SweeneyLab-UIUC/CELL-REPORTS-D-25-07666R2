from __future__ import annotations

from typing import Optional
import numpy as np
import pandas as pd
import warnings

__all__ = ["Keypoints"]


class Keypoints:
    """
    Pose tracking data for a single animal track.

    Parameters
    ----------

    frames : 1D-array-like, shape (n_frames, )

    positions : array-like, shape (n_frames, n_nodes, 2)
        Raw x, y coordinates (NaN where detection failed).

    scores : array-like, shape (n_frames, n_nodes)
        Per-node confidence scores.

    node_names : list of str

    edge_names : list of (str, str)
        Directed edges (head_node → tail_node) forming a singly linked list
        skeleton; i.e. each head appears at most once as a key.

    recording_fps : float or None

    px_to_distance : dict("ratio" : float, "unit" : str) or None
        "ratio" : Ratio of pixels to 1 of distance unit
        "unit" : str of the distance measure

    track_name : str or None
    experiment_owner : str or None

    Key attributes
    --------------
    next_node : dict  {head_name: tail_name}
        Singly linked list built from edge_names.
    """

    def __init__(
        self,
        frames,
        positions,
        scores,
        node_names: list[str],
        edge_names: list[tuple[str, str]],
        recording_fps: Optional[float],
        px_to_distance: Optional[dict] = None,
        track_name: Optional[str] = None,
        experiment_owner: Optional[str] = None,
    ):
        self.frames = np.asarray(frames, dtype=int)
        self.positions  = np.asarray(positions, dtype=float)  # (n_frames, n_nodes, 2)
        self.scores     = np.asarray(scores,    dtype=float)  # (n_frames, n_nodes)
        self.node_names = list(node_names)
        self.edge_names = list(edge_names)
        self._node_idx  = {name: i for i, name in enumerate(node_names)}
        # Singly linked list: head → tail
        self.next_node  = {head: tail for head, tail in edge_names}

        self.recording_fps = recording_fps
        self.px_to_distance_ratios = px_to_distance
        self.track_name = track_name
        self.experiment_owner = experiment_owner

    def __repr__(self) -> str:
        return (
            f"Keypoints(track={self.track_name!r}, owner={self.experiment_owner!r}, "
            f"frames={len(self.frames)}, nodes={self.node_names})"
        )

    @classmethod
    def from_dict(cls, input_dict: dict) -> Keypoints:
        frames = input_dict["frames"]
        positions = input_dict["positions"]
        scores = input_dict["scores"]
        node_names = input_dict["node_names"]
        edge_names = input_dict["edge_names"]
        recording_fps = input_dict["fps"]

        px_to_distance = input_dict.get("px_to_distance", None)
        track_name = input_dict.get("track_name", None)
        experiment_owner = input_dict.get("experiment_owner", None)

        return cls(
            frames=frames, positions=positions, scores=scores,
            node_names=node_names, edge_names=edge_names,
            recording_fps=recording_fps, px_to_distance=px_to_distance,
            track_name=track_name, experiment_owner=experiment_owner,
        )

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _resolve_node(self, node) -> int:
        """Accept node name (str) or integer index; return integer index."""
        if isinstance(node, str):
            return self._node_idx[node]
        return int(node)

    def _resolve_positions(self, node_or_positions) -> np.ndarray:
        """
        Return an (n_frames, 2) position array from a node name/index or a
        pre-computed position array (e.g. the output of centroid()).
        """
        if isinstance(node_or_positions, np.ndarray):
            return node_or_positions.copy()
        idx = self._resolve_node(node_or_positions)
        return self.positions[:, idx, :].copy()

    def _emplace_node(self, node_pos: np.ndarray, name: str) -> None:
        dims = self.positions.shape[0::2]

        if (dims[0] == node_pos.shape[0]) and (dims[1] == node_pos.shape[-1]):
            if len(node_pos.shape) < 3:
                node_pos = node_pos.reshape(dims[0], -1, dims[1])
            self.positions = np.concatenate([self.positions, node_pos], axis=1)
            self.node_names.append(name)
            self._node_idx[name] = len(self._node_idx)
        else:
            raise ValueError(
                f"Emplaced node {name} of shape {str(node_pos.shape)} to keypoint shape {str(self.positions.shape)}"
            )

    def _frames_to_times(self, frame=None):
        if self.recording_fps is None:
            exp_name = self.experiment_owner or "EXPERIMENT_NAME_MISSING"
            track_name = self.track_name or "TRACK_NAME_MISSING"
            raise ValueError(
                f"track name {track_name} in {exp_name} is missing a valid numeric fps value "
                f"and cannot convert _frames_to_times()"
            )
        if frame is None:
            return pd.to_timedelta(self.frames / self.recording_fps, unit="s")
        else:
            return pd.to_timedelta(frame / self.recording_fps, unit="s")

    def _px_to_distance(self, distances, as_scalar=True):
        if self.px_to_distance_ratios is None:
            exp_name = self.experiment_owner or "EXPERIMENT_NAME_MISSING"
            track_name = self.track_name or "TRACK_NAME_MISSING"
            raise ValueError(
                f"track name {track_name} in {exp_name} is missing a valid px_to_distance_ratios "
                f"and cannot convert _px_to_distance()"
            )
        if not isinstance(distances, np.ndarray):
            distances = np.asarray(distances)
        if len(distances.shape) == 3:
            if as_scalar:
                results = np.full((*distances.shape[:-1], 1), np.nan)
            else:
                results = np.full_like(distances, np.nan)
            for i in range(distances.shape[1]):
                results[:, i, :] = self._px_to_distance(distances[:, i, :], as_scalar)
            results = results.squeeze(-1)
        elif len(distances.shape) == 2:
            results = np.column_stack([
                np.array(distances[:, 0] * self.px_to_distance_ratios["ratio"]),
                np.array(distances[:, 1] * self.px_to_distance_ratios["ratio"]),
            ])
            if as_scalar:
                results = np.linalg.norm(results, axis=1)
        elif len(distances.shape) == 1:
            results = distances * self.px_to_distance_ratios["ratio"]
        return results

    def _update_positions_from_warp(self, warp_matrix):
        raise NotImplementedError

    # ------------------------------------------------------------------
    # 1. Distance between two nodes
    # ------------------------------------------------------------------
    def displacement(self, node_a, as_px=True, node_b=None, frame=None, origin=None) -> np.ndarray | float:
        """
        Euclidean displacement between nodes. Strictly to be used externally and not called
        within internal functions.

        Parameters
        ----------
        node_a : str or int
        node_b : str or int, optional
            If given, returns the displacement between node a and node b.
            If None, returns the displacement frame-to-frame displacement from the origin
        frame : int, optional
            If given, returns the displacement at that frame from the origin
            If None, returns the displacement between all frames
        origin: int, optional
            if given, set the origin as the node position at frame = origin
            if None, set the origin as the node position at frame = 0

        Returns
        -------
        float or np.ndarray
        """
        ia = self._resolve_node(node_a)

        if node_b is not None:
            ib = self._resolve_node(node_b)
            if frame is not None:
                results = self.positions[frame, ia] - self.positions[frame, ib]  # (2,)
            else:
                results = self.positions[:, ia] - self.positions[:, ib]          # (n_frames, 2)
        else:
            origin_frame = origin if origin is not None else 0
            origin_pos = self.positions[origin_frame, ia]   # (2,)
            if frame is not None:
                results = self.positions[frame, ia] - origin_pos    # (2,)
            else:
                results = self.positions[:, ia] - origin_pos        # (n_frames, 2)

        if not as_px:
            results = self._px_to_distance(results, as_scalar=False)

        if results.ndim == 1:
            return float(np.linalg.norm(results))
        else:
            return np.linalg.norm(results, axis=1)

    def distance(self, node_a, as_px=True, node_b=None) -> np.ndarray:
        """
        Euclidean distance between nodes. Strictly to be used externally and not called
        within internal functions. Cumulative distance from origin frame.

        Parameters
        ----------
        node_a : str or int
        node_b : str or int, optional
            If given, returns the distances between node a and node b.
            If None, returns the frame-to-frame distances starting from the origin frame

        Returns
        -------
        float or np.ndarray
        """
        ia = self._resolve_node(node_a)

        if node_b is not None:
            ib = self._resolve_node(node_b)
            results = self.positions[:, ia] - self.positions[:, ib]         # (n_frames, 2)
            if not as_px:
                results = self._px_to_distance(results, as_scalar=False)
            results = np.linalg.norm(results, axis=1)                       # (n_frames, )
        else:
            results = np.diff(self.positions[:, ia], axis=0)                # (n_frames-1, 2)
            if not as_px:
                results = self._px_to_distance(results, as_scalar=False)
            results = np.linalg.norm(results, axis=1)                       # (n_frames-1, )
            results_clean = results.copy()
            results_clean[np.isnan(results_clean)] = 0.0
            results = np.concatenate([[0], results_clean.cumsum()])         # (n_frames, )

        return results

    # ------------------------------------------------------------------
    # 2. Relative angle between connected nodes
    # ------------------------------------------------------------------
    def angle(self, node_a, node_b, node_c=None, frame=None) -> np.ndarray | float:
        """
        Angular relationship involving two or three nodes.

        With two nodes (node_c=None):
            Returns the bearing of the vector node_a → node_b relative to the
            positive x-axis, in radians on [-π, π].

        With three nodes:
            Returns the interior angle at node_b in the chain
            node_a → node_b → node_c, in radians on [0, π].

        Parameters
        ----------
        node_a, node_b : str or int
        node_c : str or int, optional
        frame : int, optional — scalar result; None returns (n_frames,) array.

        Returns
        -------
        float or np.ndarray  (radians)
        """
        ia = self._resolve_node(node_a)
        ib = self._resolve_node(node_b)

        if frame is not None:
            pa, pb = self.positions[frame, ia], self.positions[frame, ib]
            if node_c is None:
                return float(np.arctan2(pb[1] - pa[1], pb[0] - pa[0]))
            ic = self._resolve_node(node_c)
            pc = self.positions[frame, ic]
            v1, v2 = pa - pb, pc - pb
            cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-12)
            return float(np.arccos(np.clip(cos_a, -1.0, 1.0)))

        pa = self.positions[:, ia]   # (n_frames, 2)
        pb = self.positions[:, ib]
        if node_c is None:
            return np.arctan2(pb[:, 1] - pa[:, 1], pb[:, 0] - pa[:, 0])
        ic = self._resolve_node(node_c)
        pc = self.positions[:, ic]
        v1 = pa - pb
        v2 = pc - pb
        dot   = np.einsum('fi,fi->f', v1, v2)
        norms = np.linalg.norm(v1, axis=1) * np.linalg.norm(v2, axis=1) + 1e-12
        return np.arccos(np.clip(dot / norms, -1.0, 1.0))

    # ------------------------------------------------------------------
    # 3. Centroid
    # ------------------------------------------------------------------
    def centroid(self, nodes=None, method="mean", emplace=False, name=None) -> np.ndarray:
        """
        Centroid of a set of keypoints at each frame.

        Parameters
        ----------
        nodes : list of str/int, optional
            Nodes to include. Defaults to all nodes.
        method : {"mean", "convex_hull"}
            "mean"         — arithmetic mean of node positions (fast).
            "convex_hull"  — centroid of the convex-hull polygon (geometric).
        emplace : bool
            if True: Add to internal node list using self._emplace_node()

        Returns
        -------
        np.ndarray, shape (n_frames, 2)
            NaN where fewer than the required number of valid nodes exist.
        """
        def _centroid_mean(pts):
            with np.errstate(all="ignore"):
                return np.nanmean(pts, axis=1)

        def _centroid_convex_hull(pts):
            from scipy.spatial import ConvexHull
            n_frames = pts.shape[0]
            result = np.full((n_frames, 2), np.nan)
            for f in range(n_frames):
                fp = pts[f]
                valid = fp[~np.isnan(fp).any(axis=1)]
                if len(valid) == 0:
                    continue
                if len(valid) < 3:
                    result[f] = valid.mean(axis=0)
                    continue
                try:
                    hull = ConvexHull(valid)
                    verts = valid[hull.vertices]
                    x, y  = verts[:, 0], verts[:, 1]
                    xn, yn = np.roll(x, -1), np.roll(y, -1)
                    cross  = x * yn - xn * y
                    area   = 0.5 * abs(cross.sum())
                    if area < 1e-10:
                        result[f] = verts.mean(axis=0)
                    else:
                        result[f, 0] = ((x + xn) * cross).sum() / (6.0 * area)
                        result[f, 1] = ((y + yn) * cross).sum() / (6.0 * area)
                except Exception:
                    result[f] = valid.mean(axis=0)
            return result

        idx = (list(range(len(self.node_names)))
               if nodes is None
               else [self._resolve_node(n) for n in nodes])
        pts = self.positions[:, idx, :]   # (n_frames, k, 2)

        if method == "convex_hull":
            result = _centroid_convex_hull(pts)
        elif method == "mean":
            result = _centroid_mean(pts)
        else:
            raise ValueError(f"Unknown centroid method: {method!r}. Use 'mean' or 'convex_hull'.")

        if emplace:
            if name is None:
                name = "centroid_" + method
            self._emplace_node(result, name=name)

        return result

    # ------------------------------------------------------------------
    # 4. Smoothed velocity
    # ------------------------------------------------------------------
    def velocity(self, node_or_positions, as_px=True, as_scalar=False) -> np.ndarray:
        """
        Frame-to-frame velocity of a node or a pre-computed position array.

        Parameters
        ----------
        node_or_positions : str, int, or np.ndarray (n_frames, 2)
            Node name/index, or any (n_frames, 2) position array such as the
            output of centroid().
        as_px : bool
            If False, convert to real-world units using px_to_distance_ratios.
        as_scalar : bool
            If True, return speed (scalar magnitude) instead of (vx, vy).

        Returns
        -------
        np.ndarray, shape (n_frames, 2) or (n_frames,) if as_scalar=True.
            Frame 0 is always NaN (no prior frame).
        """
        pos = self._resolve_positions(node_or_positions)
        vel = np.full_like(pos, np.nan)

        if self.recording_fps is None:
            exp_name = self.experiment_owner or "EXPERIMENT_NAME_MISSING"
            track_name = self.track_name or "TRACK_NAME_MISSING"
            warnings.warn(
                f"track name {track_name} in {exp_name} is missing a valid numeric fps value "
                f"and will return velocities as distance / frame"
            )
            vel[1:] = pos[1:] - pos[:-1]
            return vel

        vel[1:] = (pos[1:] - pos[:-1]) * self.recording_fps

        if not as_px:
            vel = self._px_to_distance(vel, as_scalar=False)
        if as_scalar:
            vel = np.linalg.norm(vel, axis=1)

        return vel

    # ------------------------------------------------------------------
    # 5. Periods of motionlessness
    # ------------------------------------------------------------------
    def motionless_periods(self, node_or_positions, velocity_threshold,
                           min_duration=1) -> list[tuple[int, int, int]]:
        """
        Find contiguous frame ranges where the speed is below a threshold.

        Parameters
        ----------
        node_or_positions : str, int, or np.ndarray (n_frames, 2)
        velocity_threshold : float
            Speed (in the same units as velocity()) below which the subject
            is considered motionless.
        min_duration : int
            Minimum number of consecutive frames required to report a period.

        Returns
        -------
        list of (start_frame, end_frame, duration_frames) tuples
            Ranges are inclusive. Frames with NaN velocity are not treated as
            motionless.
        """
        vel   = self.velocity(node_or_positions)
        speed = np.linalg.norm(vel, axis=1)             # (n_frames,)
        still = (~np.isnan(speed)) & (speed < velocity_threshold)

        periods = []
        start   = None
        for i, s in enumerate(still):
            if s and start is None:
                start = i
            elif not s and start is not None:
                duration = i - start
                if duration >= min_duration:
                    periods.append((start, i - 1, duration))
                start = None
        if start is not None:
            duration = len(still) - start
            if duration >= min_duration:
                periods.append((start, len(still) - 1, duration))
        return periods

    # ------------------------------------------------------------------
    # 6. Arena region preference
    # ------------------------------------------------------------------
    def region_preference(self, node_or_positions, n, arena_bounds=None) -> tuple[dict, np.ndarray]:
        """
        Divide the arena into 2^n rectangular regions and compute the fraction
        of valid frames spent in each.

        The arena is subdivided by alternately bisecting the x then y axis
        (quadtree style), yielding a grid of n_cols × n_rows cells where
        n_cols = 2^ceil(n/2) and n_rows = 2^floor(n/2) (total = 2^n).

        n=0 → 1 region  (whole arena)
        n=1 → 2 regions (left / right halves)
        n=2 → 4 regions (quadrants)
        n=3 → 8 regions (4 columns × 2 rows)
        n=4 → 16 regions (4 × 4 grid)

        Parameters
        ----------
        node_or_positions : str, int, or np.ndarray (n_frames, 2)
        n : int
            Subdivision level; total regions = 2^n.
        arena_bounds : (x_min, x_max, y_min, y_max), optional
            Explicit arena extent. Defaults to the bounding box of the
            trajectory (not recommended for comparing across animals).

        Returns
        -------
        preference : dict  {region_id (int, row-major) : fraction (float)}
        grid : np.ndarray (n_rows, n_cols)
            The same fractions arranged spatially; grid[0, 0] is the
            top-left region when y increases downward (image coordinates).
        """
        pos = self._resolve_positions(node_or_positions)
        valid_mask = ~np.isnan(pos).any(axis=1)
        valid_pos  = pos[valid_mask]

        if valid_pos.size == 0:
            raise ValueError("No valid (non-NaN) positions to compute region preference.")

        if arena_bounds is None:
            x_min, x_max = valid_pos[:, 0].min(), valid_pos[:, 0].max()
            y_min, y_max = valid_pos[:, 1].min(), valid_pos[:, 1].max()
        else:
            x_min, x_max, y_min, y_max = arena_bounds

        n_cols = 2 ** int(np.ceil(n / 2))
        n_rows = 2 ** int(np.floor(n / 2))

        x_edges = np.linspace(x_min, x_max, n_cols + 1)
        y_edges = np.linspace(y_min, y_max, n_rows + 1)

        col_idx = np.clip(np.searchsorted(x_edges[1:-1], pos[:, 0]), 0, n_cols - 1)
        row_idx = np.clip(np.searchsorted(y_edges[1:-1], pos[:, 1]), 0, n_rows - 1)

        grid = np.zeros((n_rows, n_cols), dtype=float)
        for r in range(n_rows):
            for c in range(n_cols):
                grid[r, c] = np.sum(valid_mask & (row_idx == r) & (col_idx == c))

        n_valid = valid_mask.sum()
        if n_valid > 0:
            grid /= n_valid

        preference = {r * n_cols + c: grid[r, c]
                      for r in range(n_rows) for c in range(n_cols)}
        return preference, grid

    # ------------------------------------------------------------------
    # Position reliability — fill and smooth
    # ------------------------------------------------------------------

    def fill_missing(self, confidence_threshold=0.0, fill_method="forward_backward") -> np.ndarray:
        """
        Replace missing or low-confidence positions by carrying forward (and
        optionally backward) the nearest good detection.

        A position is treated as missing if its coordinates are NaN **or** its
        confidence score is at or below ``confidence_threshold``.

        Parameters
        ----------
        confidence_threshold : float
            Frames where ``score <= threshold`` are considered missing.
            Default ``0.0`` replaces only true NaN positions.
        fill_method : {"forward", "forward_backward"}
            ``"forward"``          — carry the last known-good value forward;
                                     frames before the first valid detection
                                     remain NaN.
            ``"forward_backward"`` — forward-fill first, then backward-fill
                                     any remaining leading NaN using the
                                     earliest good detection.

        Returns
        -------
        np.ndarray, shape (n_frames, n_nodes, 2)
            A copy of the positions array with gaps filled.

        Example
        -------
        >>> filled = kp.fill_missing(confidence_threshold=0.3)
        >>> vel    = kp.velocity(filled[:, node_idx, :])
        """
        pos = self.positions.copy()                         # (n_frames, n_nodes, 2)

        bad = np.isnan(pos).any(axis=2)                     # (n_frames, n_nodes)
        if confidence_threshold > 0.0:
            bad |= (self.scores <= confidence_threshold)
        pos[bad] = np.nan

        n_frames, n_nodes, _ = pos.shape

        def _ffill(a):
            """Forward-fill a 1-D float array; leading NaN stays NaN."""
            out  = a.copy()
            mask = np.isnan(out)
            if not mask.any():
                return out
            idx = np.where(~mask, np.arange(n_frames), 0)
            np.maximum.accumulate(idx, out=idx)
            out = out[idx]
            first_valid = (~mask).argmax() if (~mask).any() else n_frames
            out[:first_valid] = np.nan
            return out

        for node in range(n_nodes):
            for coord in range(2):
                s = pos[:, node, coord]
                s = _ffill(s)
                if fill_method == "forward_backward":
                    s = _ffill(s[::-1])[::-1]
                pos[:, node, coord] = s

        return pos

    def smooth_positions(self, nodes=None, window=11, weighting="gaussian",
                         sigma=None, scores=None, emplace=False) -> np.ndarray:
        """
        Smooth x-y positions with a centred window of ``window`` frames.

        Each output position is a weighted average of the ``window // 2``
        frames before **and** after (i.e. a symmetric, causal-free filter).
        At boundaries the window is truncated and weights renormalised.
        NaN values inside the window are skipped (weight set to 0).

        Parameters
        ----------
        nodes : list of str/int, optional
            Nodes to include. Defaults to all nodes.
            Pass the output of ``fill_missing()`` to combine both operations.
        window : int
            Total window length in frames (forced odd internally).
            Half-width = ``window // 2``.
        weighting : {"gaussian", "confidence"}
            ``"gaussian"``    — symmetric Gaussian kernel centred at *t₀*;
                                standard deviation = ``sigma`` frames.
            ``"confidence"``  — weight for frame *t* = conf[t] /
                                Σ conf over the window around *t₀*; falls
                                back to uniform if all confidences are zero.
        sigma : float, optional
            Gaussian σ in frames.  Defaults to ``window / 4``.
        scores : np.ndarray, optional
            Shape ``(n_frames, n_nodes)`` confidence scores to use when
            ``weighting="confidence"``.  Defaults to ``self.scores``.
        emplace : bool, optional
            If True - update the referenced nodes in self.positions.

        Returns
        -------
        np.ndarray, same shape as ``positions``.

        Examples
        --------
        Gaussian smooth after filling gaps::

            filled   = kp.fill_missing(confidence_threshold=0.2)
            smoothed = kp.smooth_positions(filled, window=15, weighting="gaussian")
            vel      = kp.velocity(smoothed[:, 0, :])

        Confidence-weighted smooth::

            smoothed = kp.smooth_positions(window=21, weighting="confidence")
        """
        if window % 2 == 0:
            window += 1
        half = window // 2

        if sigma is None:
            sigma = window / 4.0

        offsets      = np.arange(-half, half + 1, dtype=float)
        gauss_kernel = np.exp(-0.5 * (offsets / sigma) ** 2)

        if nodes is None:
            nodes = self.node_names
        if not isinstance(nodes, list):
            nodes = [nodes]
        nodes = [self._resolve_node(x) for x in nodes]
        pos = self.positions[:, nodes, :]

        conf = self.scores if scores is None else np.asarray(scores, dtype=float)

        squeeze = pos.ndim == 2
        if squeeze:
            pos  = pos[:, np.newaxis, :]
            conf = conf[:, np.newaxis] if conf is not None else None

        n_frames, n_nodes, _ = pos.shape
        result = np.full_like(pos, np.nan)

        for node in range(n_nodes):
            node_conf = conf[:, node] if (conf is not None and
                                          weighting == "confidence") else None
            for coord in range(2):
                series = pos[:, node, coord]
                for i in range(n_frames):
                    lo = max(0, i - half)
                    hi = min(n_frames, i + half + 1)

                    vals = series[lo:hi]
                    valid = ~np.isnan(vals)
                    if not valid.any():
                        continue

                    if weighting == "gaussian":
                        k_lo = half - (i - lo)
                        w = gauss_kernel[k_lo: k_lo + (hi - lo)].copy()
                    else:
                        if node_conf is not None:
                            w = node_conf[lo:hi].copy()
                        else:
                            w = np.ones(hi - lo)

                    w[~valid] = 0.0
                    w_sum = w.sum()
                    if w_sum < 1e-12:
                        result[i, node, coord] = vals[valid].mean()
                    else:
                        result[i, node, coord] = np.dot(vals, w) / w_sum

        if emplace:
            self.positions[:, nodes, :] = result

        return result[:, 0, :] if squeeze else result

    # ------------------------------------------------------------------
    # Plotting helpers
    # ------------------------------------------------------------------
    def _frame_slice(self, frames):
        """Return a slice from a (start, end) tuple or None (all frames)."""
        if frames is None:
            return slice(None)
        return slice(frames[0], frames[1] + 1)

    def plot_trajectory(self, nodes, frames=None, color_by_time=True,
                        ax=None, figsize=(7, 7), alpha=0.7):
        """
        Plot the x-y trajectory of one or more keypoints.

        Parameters
        ----------
        nodes : list of str or int
            Keypoints to plot.
        frames : (start, end) tuple, optional
            Inclusive frame range. None plots all frames.
        color_by_time : bool
            If True, lines are coloured from light→dark to show time direction.
            If False, each node gets a distinct colour with a simple legend.
        ax : matplotlib.axes.Axes, optional
        figsize : (w, h)
        alpha : float

        Returns
        -------
        fig, ax
        """
        import matplotlib.pyplot as plt
        import matplotlib.colors as mcolors
        from matplotlib.collections import LineCollection

        if ax is None:
            fig, ax = plt.subplots(figsize=figsize)
        else:
            fig = ax.get_figure()

        sl  = self._frame_slice(frames)
        t   = np.arange(self.positions.shape[0])[sl]
        cmap = plt.colormaps["viridis"]

        for node in nodes:
            idx  = self._resolve_node(node)
            name = self.node_names[idx]
            pos  = self.positions[sl, idx, :]   # (n, 2)
            segment = np.stack([pos[:-1], pos[1:]], axis=1)
            if color_by_time and len(t) > 1:
                segment = LineCollection(segment, cmap=cmap, alpha=alpha, linewidth=1.2)
                norm_t = (t - t[0]) / (t[-1] - t[0])
                segment.set_array(norm_t[:-1])
                ax.add_collection(segment)
            else:
                segment = LineCollection(segment, alpha=alpha, linewidth=1.2)
                ax.add_collection(segment)

            ax.plot([], [], color=cmap(0.5), label=name, linewidth=1.5)

        if color_by_time and len(t) > 1:
            sm = plt.cm.ScalarMappable(cmap=cmap, norm=mcolors.Normalize(vmin=t[0], vmax=t[-1]))
            sm.set_array([])
            fig.colorbar(sm, ax=ax, label="Frame")

        ax.set_xlabel("x (px)")
        ax.set_ylabel("y (px)")
        ax.set_title(f"Trajectory — {self.experiment_owner or ''}")
        ax.legend(loc="best")
        ax.set_aspect("equal")
        ax.invert_yaxis()   # image coordinates: y increases downward
        return fig, ax

    def plot_heatmap(self, nodes, frames=None, bins=100, arena_bounds=None,
                     ax=None, figsize=(7, 7), cmap="hot", overlay_trajectory=False):
        """
        2-D occupancy heatmap of one or more keypoints.

        All listed nodes are pooled into a single density map.  If you need
        per-node maps call this method once per node.

        Parameters
        ----------
        nodes : list of str or int
        frames : (start, end) tuple, optional
        bins : int or (int, int)
            Number of histogram bins along (x, y).
        arena_bounds : (x_min, x_max, y_min, y_max), optional
            Fixes the histogram extent regardless of data range.
        ax : matplotlib.axes.Axes, optional
        figsize : (w, h)
        cmap : str
        overlay_trajectory : bool
            If True, draw the raw trajectory on top of the heatmap.

        Returns
        -------
        fig, ax
        """
        import matplotlib.pyplot as plt

        if ax is None:
            fig, ax = plt.subplots(figsize=figsize)
        else:
            fig = ax.get_figure()

        sl = self._frame_slice(frames)

        all_x, all_y = [], []
        for node in nodes:
            idx = self._resolve_node(node)
            pos = self.positions[sl, idx, :]
            valid = pos[~np.isnan(pos).any(axis=1)]
            all_x.append(valid[:, 0])
            all_y.append(valid[:, 1])
        all_x = np.concatenate(all_x)
        all_y = np.concatenate(all_y)

        if arena_bounds is not None:
            x_min, x_max, y_min, y_max = arena_bounds
            range_ = [[x_min, x_max], [y_min, y_max]]
        else:
            range_ = None

        h, xedges, yedges = np.histogram2d(all_x, all_y, bins=bins, range=range_)
        extent = [xedges[0], xedges[-1], yedges[-1], yedges[0]]
        im = ax.imshow(h.T[::-1], extent=extent, cmap=cmap, aspect="equal",
                       interpolation="nearest")
        fig.colorbar(im, ax=ax, label="Frame count")

        if overlay_trajectory:
            for node in nodes:
                idx  = self._resolve_node(node)
                name = self.node_names[idx]
                pos  = self.positions[sl, idx, :]
                ax.plot(pos[:, 0], pos[:, 1], color="white", alpha=0.35,
                        linewidth=0.8, label=name)
            ax.legend(loc="best", fontsize="small")

        node_labels = [self.node_names[self._resolve_node(n)] for n in nodes]
        ax.set_xlabel("x (px)")
        ax.set_ylabel("y (px)")
        ax.set_title(f"Heatmap [{', '.join(node_labels)}] — {self.experiment_owner or ''}")
        return fig, ax

    def animate_trajectory(self, nodes, frames=None, fps=25, trail_length=30,
                           figsize=(7, 7), interval=40, arena_bounds=None,
                           downsample_ratio=10):
        """
        Animated x-y trajectory with a fading trail and current-position dot.

        Parameters
        ----------
        nodes : list of str or int
        frames : (start, end) tuple, optional
        fps : float
            Used only in the title to display elapsed time.
        trail_length : int
            Number of past frames to show as a fading trail.
        figsize : (w, h)
        interval : int
            Delay between animation frames in milliseconds.
        arena_bounds : (x_min, x_max, y_min, y_max), optional
            Fixed axis limits. Defaults to data bounding box.

        Returns
        -------
        fig : matplotlib.figure.Figure
        anim : matplotlib.animation.FuncAnimation
            Call plt.show() to display, or anim.save("out.mp4") to export.
        """
        import matplotlib.pyplot as plt
        from matplotlib.animation import FuncAnimation

        sl    = self._frame_slice(frames)
        t_idx = np.arange(self.positions.shape[0])[sl]
        n_frames = len(t_idx)

        node_indices = [self._resolve_node(n) for n in nodes]
        node_labels  = [self.node_names[i] for i in node_indices]
        positions    = [self.positions[sl, i, :] for i in node_indices]

        if arena_bounds is not None:
            x_min, x_max, y_min, y_max = arena_bounds
        else:
            all_pos = np.concatenate(positions, axis=0)
            valid   = all_pos[~np.isnan(all_pos).any(axis=1)]
            pad = (valid.max(axis=0) - valid.min(axis=0)).max() * 0.05
            x_min, x_max = valid[:, 0].min() - pad, valid[:, 0].max() + pad
            y_min, y_max = valid[:, 1].min() - pad, valid[:, 1].max() + pad

        fig, ax = plt.subplots(figsize=figsize)
        ax.set_xlim(x_min, x_max)
        ax.set_ylim(y_max, y_min)   # invert y for image coordinates
        ax.set_aspect("equal")
        ax.set_xlabel("x (px)")
        ax.set_ylabel("y (px)")
        title = ax.set_title("")

        prop_cycle = plt.rcParams["axes.prop_cycle"].by_key()["color"]
        colours = [prop_cycle[i % len(prop_cycle)] for i in range(len(nodes))]

        trail_lines = [ax.plot([], [], color=c, alpha=0.6, linewidth=1.5,
                               label=lbl)[0]
                       for c, lbl in zip(colours, node_labels)]
        dots        = [ax.plot([], [], "o", color=c, markersize=6)[0]
                       for c in colours]
        ax.legend(loc="upper right", fontsize="small")

        def _init():
            for line, dot in zip(trail_lines, dots):
                line.set_data([], [])
                dot.set_data([], [])
            return trail_lines + dots + [title]

        def _update(frame_idx):
            start = max(0, frame_idx - trail_length)
            for pos, line, dot in zip(positions, trail_lines, dots):
                trail = pos[start:frame_idx + 1]
                line.set_data(trail[:, 0], trail[:, 1])
                cur = pos[frame_idx]
                if not np.isnan(cur).any():
                    dot.set_data([cur[0]], [cur[1]])
                else:
                    dot.set_data([], [])
            elapsed = t_idx[frame_idx] / fps
            title.set_text(
                f"{self.experiment_owner or ''}  |  frame {t_idx[frame_idx]}  ({elapsed:.2f} s)"
            )
            return trail_lines + dots + [title]

        anim = FuncAnimation(
            fig, _update,
            frames=range(0, n_frames, downsample_ratio),
            init_func=_init, interval=interval, blit=True,
        )
        return fig, anim


if __name__ == "__main__":
    pass
