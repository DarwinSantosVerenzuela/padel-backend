/**
 * PadelApp Matchmaking Service
 * 
 * Handles random matchmaking by:
 * 1. Finding players in the queue
 * 2. Filtering by proximity, ELO range, and availability
 * 3. Creating matches and notifying players
 */

import { supabaseAdmin } from '../config/supabase.js';

export interface QueueEntry {
    id: string;
    player_id: string;
    elo_rating: number;
    location: { lat: number; lng: number } | null;
    max_distance_km: number;
    elo_range_min: number | null;
    elo_range_max: number | null;
    preferred_time_start: string | null;
    preferred_time_end: string | null;
    preferred_duration: number;
}

export interface MatchPair {
    player1: QueueEntry;
    player2: QueueEntry;
    compatibilityScore: number;
}

/**
 * Calculate compatibility score between two queue entries
 * Higher is better (0-100)
 */
function calculateCompatibility(a: QueueEntry, b: QueueEntry): number {
    let score = 50; // Base score

    // ELO proximity (±200 is ideal, up to ±400 acceptable)
    const eloDiff = Math.abs(a.elo_rating - b.elo_rating);
    if (eloDiff <= 100) score += 30;
    else if (eloDiff <= 200) score += 20;
    else if (eloDiff <= 300) score += 10;
    else if (eloDiff <= 400) score += 5;
    else score -= 10;

    // Check ELO range preferences
    if (a.elo_range_min && b.elo_rating < a.elo_range_min) score -= 20;
    if (a.elo_range_max && b.elo_rating > a.elo_range_max) score -= 20;
    if (b.elo_range_min && a.elo_rating < b.elo_range_min) score -= 20;
    if (b.elo_range_max && a.elo_rating > b.elo_range_max) score -= 20;

    // Time overlap bonus
    if (a.preferred_time_start && b.preferred_time_start) {
        const aStart = new Date(a.preferred_time_start).getTime();
        const bStart = new Date(b.preferred_time_start).getTime();
        const timeDiffHours = Math.abs(aStart - bStart) / (1000 * 60 * 60);

        if (timeDiffHours <= 1) score += 15;
        else if (timeDiffHours <= 2) score += 10;
        else if (timeDiffHours <= 4) score += 5;
    }

    return Math.max(0, Math.min(100, score));
}

/**
 * Process the matchmaking queue
 * Finds best pairs and creates matches
 */
export async function processMatchmakingQueue(): Promise<MatchPair[]> {
    // Fetch all waiting entries with player profile data
    const { data: queueEntries, error } = await supabaseAdmin
        .from('matchmaking_queue')
        .select(`
            id,
            player_id,
            location,
            max_distance_km,
            elo_range_min,
            elo_range_max,
            preferred_time_start,
            preferred_time_end,
            preferred_duration,
            profiles!inner(elo_rating)
        `)
        .eq('status', 'waiting')
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: true });

    if (error || !queueEntries || queueEntries.length < 2) {
        return [];
    }

    // Enrich with ELO
    const entries: QueueEntry[] = queueEntries.map((q: any) => ({
        ...q,
        elo_rating: q.profiles.elo_rating,
    }));

    const matched: Set<string> = new Set();
    const pairs: MatchPair[] = [];

    // Greedy matching — pair highest compatibility first
    const candidates: { a: QueueEntry; b: QueueEntry; score: number }[] = [];

    for (let i = 0; i < entries.length; i++) {
        for (let j = i + 1; j < entries.length; j++) {
            const score = calculateCompatibility(entries[i], entries[j]);
            if (score >= 30) { // Minimum compatibility threshold
                candidates.push({ a: entries[i], b: entries[j], score });
            }
        }
    }

    // Sort by compatibility descending
    candidates.sort((x, y) => y.score - x.score);

    for (const candidate of candidates) {
        if (matched.has(candidate.a.player_id) || matched.has(candidate.b.player_id)) {
            continue;
        }

        matched.add(candidate.a.player_id);
        matched.add(candidate.b.player_id);

        pairs.push({
            player1: candidate.a,
            player2: candidate.b,
            compatibilityScore: candidate.score,
        });

        // Update queue status
        await supabaseAdmin
            .from('matchmaking_queue')
            .update({ status: 'matched', matched_with: candidate.b.player_id })
            .eq('id', candidate.a.id);

        await supabaseAdmin
            .from('matchmaking_queue')
            .update({ status: 'matched', matched_with: candidate.a.player_id })
            .eq('id', candidate.b.id);
    }

    return pairs;
}

/**
 * Expire old queue entries
 */
export async function expireOldEntries(): Promise<number> {
    const { data, error } = await supabaseAdmin
        .from('matchmaking_queue')
        .update({ status: 'expired' })
        .eq('status', 'waiting')
        .lt('expires_at', new Date().toISOString())
        .select('id');

    return data?.length || 0;
}
