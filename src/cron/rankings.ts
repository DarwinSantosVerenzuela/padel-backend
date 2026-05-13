import cron from 'node-cron';
import { supabaseAdmin } from '../config/supabase.js';
import { calculateEloChanges, calculateConfidence } from '../services/elo.js';

export function startRankingsCron() {
    // Process completed matches and update ELO — every minute
    cron.schedule('* * * * *', async () => {
        try {
            // Find completed matches that haven't been ELO-processed yet
            const { data: matches } = await supabaseAdmin
                .from('matches')
                .select('*, players:match_players(*, profile:profiles(id, elo_rating, elo_matches_played))')
                .eq('status', 'completed')
                .eq('elo_change_team_a', 0)
                .not('winner_team', 'is', null)
                .limit(10);

            if (!matches || matches.length === 0) return;

            for (const match of matches) {
                const teamA = match.players.filter((p: any) => p.team === 'a').map((p: any) => p.profile);
                const teamB = match.players.filter((p: any) => p.team === 'b').map((p: any) => p.profile);

                if (teamA.length === 0 || teamB.length === 0) continue;

                const results = calculateEloChanges(teamA, teamB, match.winner_team, undefined, match.match_type === 'challenge');

                // Update each player's ELO
                for (const result of results) {
                    await supabaseAdmin.from('profiles').update({
                        elo_rating: result.newRating,
                        elo_matches_played: supabaseAdmin.rpc ? undefined : result.oldRating, // handled below
                        elo_confidence: calculateConfidence((teamA.find((p: any) => p.id === result.playerId) || teamB.find((p: any) => p.id === result.playerId))?.elo_matches_played + 1 || 1),
                        elo_highest: Math.max(result.newRating, (teamA.find((p: any) => p.id === result.playerId) || teamB.find((p: any) => p.id === result.playerId))?.elo_highest || 0),
                    }).eq('id', result.playerId);

                    // Increment matches played
                    await supabaseAdmin.rpc('increment_elo_matches', { user_id: result.playerId });

                    // Update match_players with before/after
                    await supabaseAdmin.from('match_players').update({ elo_before: result.oldRating, elo_after: result.newRating })
                        .eq('match_id', match.id).eq('player_id', result.playerId);
                }

                // Mark match as ELO-processed
                const teamAChange = results.filter(r => teamA.some((p: any) => p.id === r.playerId)).reduce((s, r) => s + r.change, 0);
                const teamBChange = results.filter(r => teamB.some((p: any) => p.id === r.playerId)).reduce((s, r) => s + r.change, 0);
                await supabaseAdmin.from('matches').update({ elo_change_team_a: teamAChange, elo_change_team_b: teamBChange }).eq('id', match.id);
            }
        } catch (err) {
            console.error('❌ Rankings cron error:', err);
        }
    });
}
