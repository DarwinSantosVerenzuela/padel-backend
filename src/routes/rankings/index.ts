import { FastifyInstance } from 'fastify';
import { createUserClient } from '../../config/supabase.js';

export async function rankingsRoutes(app: FastifyInstance) {
    // Global leaderboard
    app.get('/', async (request) => {
        const { city, country, limit = 50, offset = 0 } = request.query as any;
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);
        let query = client.from('profiles').select('id, username, display_name, avatar_url, elo_rating, elo_matches_played, elo_confidence, elo_highest, city, country, is_verified, is_premium')
            .gte('elo_matches_played', 1).order('elo_rating', { ascending: false }).range(offset, offset + limit - 1);
        if (city) query = query.eq('city', city);
        if (country) query = query.eq('country', country);
        const { data, error } = await query;
        if (error) throw new Error(error.message);
        return { data };
    });
}
