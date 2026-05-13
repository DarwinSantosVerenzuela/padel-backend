/**
 * PadelApp ELO Rating Service
 * 
 * Adapted ELO system for padel doubles:
 * - Base rating: 1200
 * - K-factor varies by experience
 * - Team rating = average of both players
 * - Bonus/penalty for score margins
 */

export interface EloPlayer {
    id: string;
    elo_rating: number;
    elo_matches_played: number;
}

export interface EloResult {
    playerId: string;
    oldRating: number;
    newRating: number;
    change: number;
}

export interface MatchScore {
    setsTeamA: number[];
    setsTeamB: number[];
}

/**
 * Get K-factor based on number of matches played
 * - New players (< 10 matches): K = 40 (faster adjustment)
 * - Intermediate (10-30): K = 24
 * - Experienced (> 30): K = 16 (more stable)
 */
function getKFactor(matchesPlayed: number): number {
    if (matchesPlayed < 10) return 40;
    if (matchesPlayed <= 30) return 24;
    return 16;
}

/**
 * Calculate expected score between two ratings
 */
function expectedScore(ratingA: number, ratingB: number): number {
    return 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400));
}

/**
 * Calculate score margin bonus (0-15% extra based on dominance)
 */
function getMarginBonus(score: MatchScore): number {
    let totalDiff = 0;
    let totalSets = score.setsTeamA.length;

    for (let i = 0; i < totalSets; i++) {
        totalDiff += Math.abs(score.setsTeamA[i] - score.setsTeamB[i]);
    }

    const avgDiff = totalDiff / totalSets;

    // Bonus scales: 0 diff = 0%, 3+ diff average = 15%
    return Math.min(avgDiff * 0.05, 0.15);
}

/**
 * Calculate ELO changes for a doubles match
 * 
 * @param teamA - Array of 2 players on team A
 * @param teamB - Array of 2 players on team B
 * @param winner - 'a' or 'b'
 * @param score - Optional score for margin bonus
 * @param isChallenge - If true and upset occurs, apply 1.5x bonus
 */
export function calculateEloChanges(
    teamA: EloPlayer[],
    teamB: EloPlayer[],
    winner: 'a' | 'b',
    score?: MatchScore,
    isChallenge: boolean = false
): EloResult[] {
    const teamARating = teamA.reduce((sum, p) => sum + p.elo_rating, 0) / teamA.length;
    const teamBRating = teamB.reduce((sum, p) => sum + p.elo_rating, 0) / teamB.length;

    const expectedA = expectedScore(teamARating, teamBRating);
    const expectedB = 1 - expectedA;

    const actualA = winner === 'a' ? 1 : 0;
    const actualB = winner === 'b' ? 1 : 0;

    // Determine if upset occurred (for challenge bonus)
    const isUpset = (
        (winner === 'a' && teamARating < teamBRating - 100) ||
        (winner === 'b' && teamBRating < teamARating - 100)
    );
    const challengeMultiplier = isChallenge && isUpset ? 1.5 : 1;

    // Score margin bonus
    const marginBonus = score ? getMarginBonus(score) : 0;

    const results: EloResult[] = [];

    // Calculate for each player in team A
    for (const player of teamA) {
        const k = getKFactor(player.elo_matches_played);
        let change = Math.round(k * (actualA - expectedA) * challengeMultiplier);

        if (actualA === 1 && marginBonus > 0) {
            change = Math.round(change * (1 + marginBonus));
        }

        results.push({
            playerId: player.id,
            oldRating: player.elo_rating,
            newRating: Math.max(100, player.elo_rating + change), // Floor at 100
            change
        });
    }

    // Calculate for each player in team B
    for (const player of teamB) {
        const k = getKFactor(player.elo_matches_played);
        let change = Math.round(k * (actualB - expectedB) * challengeMultiplier);

        if (actualB === 1 && marginBonus > 0) {
            change = Math.round(change * (1 + marginBonus));
        }

        results.push({
            playerId: player.id,
            oldRating: player.elo_rating,
            newRating: Math.max(100, player.elo_rating + change),
            change
        });
    }

    return results;
}

/**
 * Calculate ELO confidence (0.00 to 1.00)
 * Based on number of matches played — more matches = higher confidence
 */
export function calculateConfidence(matchesPlayed: number): number {
    // Logistic curve: approaches 1.0 around 30+ matches
    const confidence = 1 - Math.exp(-0.1 * matchesPlayed);
    return Math.round(confidence * 100) / 100;
}
