import { FastifyInstance } from 'fastify';
import { authMiddleware, AuthenticatedRequest } from '../../middleware/auth.js';
import { createUserClient } from '../../config/supabase.js';
import { z } from 'zod';

export async function courtsRoutes(app: FastifyInstance) {
    app.get('/nearby', async (request) => {
        const { lat, lng, radius_km = 25, limit = 20 } = z.object({
            lat: z.coerce.number(), lng: z.coerce.number(),
            radius_km: z.coerce.number().default(25), limit: z.coerce.number().default(20),
        }).parse(request.query);
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);
        const { data, error } = await client.rpc('find_nearby_courts', { user_lat: lat, user_lng: lng, radius_km, max_results: limit });
        if (error) throw new Error(error.message);
        return { data };
    });

    app.get<{ Params: { slug: string } }>('/:slug', async (request) => {
        const { slug } = request.params;
        const token = request.headers.authorization?.substring(7) || '';
        const client = createUserClient(token);
        const { data, error } = await client.from('courts')
            .select('*, menu_categories:court_menu_categories(*, items:court_menu_items(*)), reviews:court_reviews(*, user:profiles(id, username, display_name, avatar_url))')
            .eq('slug', slug).single();
        if (error) throw new Error(error.message);
        return { data };
    });

    app.post('/', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({
            name: z.string().min(1).max(200), address: z.string().min(1),
            latitude: z.number(), longitude: z.number(),
            city: z.string().optional(), country: z.string().optional(),
            phone: z.string().optional(), email: z.string().email().optional(),
            total_courts: z.number().default(1), surface_type: z.string().default('artificial_grass'),
            is_indoor: z.boolean().default(false), has_restaurant: z.boolean().default(false),
            has_bar: z.boolean().default(false), price_per_hour: z.number().optional(),
            currency: z.string().default('USD'),
        }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const slug = body.name.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '-' + Date.now().toString(36);
        const { data, error } = await client.from('courts').insert({ ...body, slug, owner_id: req.userId }).select().single();
        if (error) throw new Error(error.message);
        return { data };
    });

    app.post<{ Params: { courtId: string } }>('/:courtId/menu/categories', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({ name: z.string(), name_en: z.string().optional(), display_order: z.number().default(0) }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('court_menu_categories').insert({ ...body, court_id: request.params.courtId }).select().single();
        if (error) throw new Error(error.message);
        return { data };
    });

    app.post<{ Params: { courtId: string } }>('/:courtId/menu/items', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({ category_id: z.string().uuid(), name: z.string(), name_en: z.string().optional(), price: z.number(), is_available: z.boolean().default(true) }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('court_menu_items').insert({ ...body, court_id: request.params.courtId }).select().single();
        if (error) throw new Error(error.message);
        return { data };
    });

    app.post<{ Params: { courtId: string } }>('/:courtId/book', { preHandler: authMiddleware }, async (request) => {
        const req = request as AuthenticatedRequest;
        const body = z.object({ start_time: z.string().datetime(), end_time: z.string().datetime(), court_number: z.number().optional(), table_reservation: z.boolean().default(false), notes: z.string().optional(), menu_orders: z.array(z.object({ item_id: z.string().uuid(), quantity: z.number() })).optional() }).parse(request.body);
        const client = createUserClient(req.accessToken);
        const { data, error } = await client.from('bookings').insert({ court_id: request.params.courtId, booked_by: req.userId, ...body }).select().single();
        if (error) throw new Error(error.message);
        return { data };
    });
}
