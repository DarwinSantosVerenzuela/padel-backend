-- ============================================
-- ProNet — Shop & E-commerce Tables
-- Migration: 008_shop_tables
-- ============================================

-- ============================================
-- STORES (tiendas — ProNet official + partners)
-- ============================================
CREATE TABLE IF NOT EXISTS public.stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES public.profiles(id),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(200) UNIQUE NOT NULL,
    description TEXT,
    logo_url TEXT,
    cover_image_url TEXT,
    website TEXT,
    is_official BOOLEAN DEFAULT FALSE,
    commission_rate DECIMAL(4,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================
-- PRODUCT CATEGORIES (categorías)
-- ============================================
CREATE TABLE IF NOT EXISTS public.product_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    name_en VARCHAR(100),
    slug VARCHAR(100) UNIQUE NOT NULL,
    icon VARCHAR(10),
    display_order SMALLINT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- ============================================
-- PRODUCTS (catálogo)
-- ============================================
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id),
    category_id UUID REFERENCES public.product_categories(id),
    name VARCHAR(300) NOT NULL,
    slug VARCHAR(300) UNIQUE NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    compare_at_price DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'USD',
    images TEXT[] DEFAULT '{}',
    sizes TEXT[] DEFAULT '{}',
    colors TEXT[] DEFAULT '{}',
    stock INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    avg_rating DECIMAL(2,1) DEFAULT 0,
    total_reviews INTEGER DEFAULT 0,
    total_sold INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_products_store ON public.products(store_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_featured ON public.products(is_featured) WHERE is_featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_products_active_rating ON public.products(is_active, avg_rating DESC);
CREATE INDEX IF NOT EXISTS idx_products_slug ON public.products(slug);

-- ============================================
-- PRODUCT VARIANTS (variantes talla/color)
-- ============================================
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    size VARCHAR(20),
    color VARCHAR(50),
    sku VARCHAR(100) UNIQUE,
    stock INTEGER DEFAULT 0,
    price_override DECIMAL(10,2),
    is_active BOOLEAN DEFAULT TRUE
);

-- ============================================
-- CART ITEMS (carrito por usuario)
-- ============================================
CREATE TABLE IF NOT EXISTS public.cart_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    variant_id UUID REFERENCES public.product_variants(id),
    quantity SMALLINT DEFAULT 1 CHECK (quantity > 0),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, product_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user ON public.cart_items(user_id);

-- ============================================
-- ORDERS (pedidos)
-- ============================================
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id),
    order_number VARCHAR(20) UNIQUE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded'
    )),
    subtotal DECIMAL(10,2),
    shipping_cost DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'USD',
    shipping_address JSONB,
    payment_method VARCHAR(30),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN (
        'pending', 'paid', 'failed', 'refunded'
    )),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_user_date ON public.orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);

-- ============================================
-- ORDER ITEMS (líneas de pedido)
-- ============================================
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    variant_id UUID REFERENCES public.product_variants(id),
    store_id UUID NOT NULL REFERENCES public.stores(id),
    product_name VARCHAR(300) NOT NULL,
    product_image TEXT,
    size VARCHAR(20),
    color VARCHAR(50),
    quantity SMALLINT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);

-- ============================================
-- PRODUCT REVIEWS (reseñas)
-- ============================================
CREATE TABLE IF NOT EXISTS public.product_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id),
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    photos TEXT[] DEFAULT '{}',
    is_verified_purchase BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(product_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_product_reviews_product ON public.product_reviews(product_id);

-- ============================================
-- WISHLISTS (lista de deseos)
-- ============================================
CREATE TABLE IF NOT EXISTS public.wishlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlists_user ON public.wishlists(user_id);

-- ============================================
-- TRIGGERS — set_updated_at
-- ============================================
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.stores
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- TRIGGER — update_product_rating
-- (mirrors update_court_rating from 003_functions)
-- ============================================
CREATE OR REPLACE FUNCTION public.update_product_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.products SET
        avg_rating = (SELECT ROUND(AVG(rating)::numeric, 1) FROM public.product_reviews WHERE product_id = COALESCE(NEW.product_id, OLD.product_id)),
        total_reviews = (SELECT COUNT(*) FROM public.product_reviews WHERE product_id = COALESCE(NEW.product_id, OLD.product_id))
    WHERE id = COALESCE(NEW.product_id, OLD.product_id);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_product_review_change
    AFTER INSERT OR UPDATE OR DELETE ON public.product_reviews
    FOR EACH ROW EXECUTE FUNCTION public.update_product_rating();

-- ============================================
-- TRIGGER — generate_order_number
-- Format: PN-YYYYMMDD-XXXX (random 4 alphanumeric)
-- ============================================
CREATE OR REPLACE FUNCTION public.generate_order_number()
RETURNS TRIGGER AS $$
DECLARE
    v_chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    v_rand TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..4 LOOP
        v_rand := v_rand || substr(v_chars, floor(random() * length(v_chars) + 1)::integer, 1);
    END LOOP;
    NEW.order_number := 'PN-' || to_char(NOW(), 'YYYYMMDD') || '-' || v_rand;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_order_generate_number
    BEFORE INSERT ON public.orders
    FOR EACH ROW
    WHEN (NEW.order_number IS NULL)
    EXECUTE FUNCTION public.generate_order_number();

-- ============================================
-- TRIGGER — update_product_sold_count
-- Increments total_sold when order status → 'delivered'
-- ============================================
CREATE OR REPLACE FUNCTION public.update_product_sold_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
        UPDATE public.products p SET
            total_sold = p.total_sold + oi.quantity
        FROM public.order_items oi
        WHERE oi.order_id = NEW.id AND oi.product_id = p.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_order_delivered
    AFTER UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.update_product_sold_count();

-- ============================================
-- ANALYTICS EXTENSION — expand action + target_type
-- ============================================

-- Expand action CHECK constraint to include shop actions
ALTER TABLE public.user_activity_log
DROP CONSTRAINT IF EXISTS user_activity_log_action_check;

ALTER TABLE public.user_activity_log
ADD CONSTRAINT user_activity_log_action_check CHECK (action IN (
    -- Posts
    'post_create', 'post_like', 'post_dislike', 'post_repost',
    -- Comments
    'comment_create', 'comment_like',
    -- Social
    'follow', 'unfollow',
    -- Matches
    'match_play', 'match_win', 'match_lose',
    -- Challenges
    'challenge_send', 'challenge_accept',
    -- Courts
    'court_visit', 'court_review', 'court_bookmark',
    -- Discovery
    'profile_view', 'search_player',
    -- Messaging
    'chat_message',
    -- Sharing
    'share_post',
    -- Media & Location
    'photo_upload', 'location_share',
    -- Reactions
    'emoji_react',
    -- Auth
    'password_reset',
    -- Shop (new)
    'product_view', 'product_purchase', 'cart_add', 'cart_remove',
    'store_visit', 'wishlist_add', 'wishlist_remove', 'shop_search'
));

-- Expand target_type CHECK constraint to include shop types
ALTER TABLE public.user_activity_log
DROP CONSTRAINT IF EXISTS user_activity_log_target_type_check;

ALTER TABLE public.user_activity_log
ADD CONSTRAINT user_activity_log_target_type_check CHECK (target_type IN (
    'post', 'comment', 'user', 'match', 'court', 'challenge',
    -- Shop (new)
    'product', 'store', 'order'
));

-- ============================================
-- VIEW — shop_user_metrics (per user)
-- ============================================
CREATE OR REPLACE VIEW public.shop_user_metrics AS
SELECT
    p.id AS user_id,
    p.display_name,
    p.username,
    COALESCE(SUM(o.total), 0)::DECIMAL(10,2) AS total_spent,
    COUNT(DISTINCT o.id)::INTEGER AS orders_count,
    CASE WHEN COUNT(DISTINCT o.id) > 0
        THEN ROUND((SUM(o.total) / COUNT(DISTINCT o.id))::numeric, 2)
        ELSE 0
    END::DECIMAL(10,2) AS avg_order_value,
    (
        SELECT pc.name FROM public.order_items oi2
        JOIN public.products pr ON pr.id = oi2.product_id
        JOIN public.product_categories pc ON pc.id = pr.category_id
        JOIN public.orders o2 ON o2.id = oi2.order_id
        WHERE o2.user_id = p.id
        GROUP BY pc.name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS favorite_category,
    (SELECT COUNT(*)::INTEGER FROM public.cart_items ci WHERE ci.user_id = p.id) AS items_in_cart,
    (SELECT COUNT(*)::INTEGER FROM public.wishlists w WHERE w.user_id = p.id) AS wishlist_count
FROM public.profiles p
LEFT JOIN public.orders o ON o.user_id = p.id AND o.payment_status = 'paid'
GROUP BY p.id, p.display_name, p.username;

-- ============================================
-- VIEW — store_performance (per store)
-- ============================================
CREATE OR REPLACE VIEW public.store_performance AS
SELECT
    s.id AS store_id,
    s.name AS store_name,
    s.slug,
    s.is_official,
    COALESCE(SUM(oi.total_price), 0)::DECIMAL(10,2) AS total_revenue,
    COUNT(DISTINCT oi.order_id)::INTEGER AS orders_count,
    (SELECT COUNT(*)::INTEGER FROM public.products pr WHERE pr.store_id = s.id AND pr.is_active = TRUE) AS products_count,
    COALESCE((
        SELECT ROUND(AVG(prvw.avg_rating)::numeric, 1)
        FROM public.products prvw
        WHERE prvw.store_id = s.id AND prvw.total_reviews > 0
    ), 0)::DECIMAL(2,1) AS avg_rating,
    (
        SELECT pc.name FROM public.order_items oi2
        JOIN public.products pr ON pr.id = oi2.product_id
        JOIN public.product_categories pc ON pc.id = pr.category_id
        WHERE oi2.store_id = s.id
        GROUP BY pc.name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS top_category
FROM public.stores s
LEFT JOIN public.order_items oi ON oi.store_id = s.id
LEFT JOIN public.orders o ON o.id = oi.order_id AND o.payment_status = 'paid'
GROUP BY s.id, s.name, s.slug, s.is_official;

-- ============================================
-- SEED DATA — Product Categories
-- ============================================
INSERT INTO public.product_categories (name, name_en, slug, icon, display_order) VALUES
    ('Palas y Raquetas', 'Rackets & Paddles', 'rackets', '🏓', 1),
    ('Ropa Deportiva', 'Sportswear', 'clothing', '👕', 2),
    ('Calzado', 'Footwear', 'shoes', '👟', 3),
    ('Accesorios', 'Accessories', 'accessories', '🎒', 4),
    ('Merch ProNet', 'ProNet Merch', 'merch', '🏆', 5)
ON CONFLICT (slug) DO NOTHING;

-- ============================================
-- SEED DATA — ProNet Official Store
-- ============================================
INSERT INTO public.stores (name, slug, description, is_official, is_featured, is_active) VALUES
    ('ProNet Official', 'pronet-official',
     'La tienda oficial de ProNet. Encuentra las mejores palas, ropa deportiva y accesorios para llevar tu juego al siguiente nivel.',
     TRUE, TRUE, TRUE)
ON CONFLICT (slug) DO NOTHING;

-- ============================================
-- SEED DATA — Sample Products
-- ============================================
DO $$
DECLARE
    v_store_id UUID;
    v_cat_rackets UUID;
    v_cat_clothing UUID;
    v_cat_shoes UUID;
    v_cat_accessories UUID;
    v_cat_merch UUID;
BEGIN
    SELECT id INTO v_store_id FROM public.stores WHERE slug = 'pronet-official' LIMIT 1;
    SELECT id INTO v_cat_rackets FROM public.product_categories WHERE slug = 'rackets' LIMIT 1;
    SELECT id INTO v_cat_clothing FROM public.product_categories WHERE slug = 'clothing' LIMIT 1;
    SELECT id INTO v_cat_shoes FROM public.product_categories WHERE slug = 'shoes' LIMIT 1;
    SELECT id INTO v_cat_accessories FROM public.product_categories WHERE slug = 'accessories' LIMIT 1;
    SELECT id INTO v_cat_merch FROM public.product_categories WHERE slug = 'merch' LIMIT 1;

    IF v_store_id IS NOT NULL THEN
        -- Rackets
        INSERT INTO public.products (store_id, category_id, name, slug, description, price, compare_at_price, images, sizes, colors, stock, is_active, is_featured, metadata) VALUES
        (v_store_id, v_cat_rackets, 'Bullpadel Vertex 04', 'bullpadel-vertex-04',
         'La pala de referencia para jugadores avanzados. Forma de diamante, carbono 18K. Máxima potencia y control en cada golpe.',
         289.99, 349.99, ARRAY['https://placehold.co/600x600/1a1a2e/e94560?text=Vertex+04'], ARRAY[]::TEXT[], ARRAY['Negro/Rojo', 'Negro/Azul'], 25, TRUE, TRUE,
         '{"brand": "Bullpadel", "weight": "360-375g", "shape": "Diamond", "level": "Advanced"}'::jsonb),

        (v_store_id, v_cat_rackets, 'Adidas Adipower CTRL 3.2', 'adidas-adipower-ctrl-32',
         'Control total con el nuevo Adipower. Núcleo de Eva Soft Performance, marco de carbono aluminizado. Ideal para jugadores de nivel intermedio-avanzado.',
         219.99, NULL, ARRAY['https://placehold.co/600x600/0f3460/e94560?text=Adipower+CTRL'], ARRAY[]::TEXT[], ARRAY['Blanco/Azul', 'Negro/Dorado'], 30, TRUE, TRUE,
         '{"brand": "Adidas", "weight": "355-370g", "shape": "Round", "level": "Intermediate-Advanced"}'::jsonb),

        (v_store_id, v_cat_rackets, 'Head Flash Pro 2024', 'head-flash-pro-2024',
         'Pala versátil para todos los niveles. Tecnología Graphene 360+ para mayor estabilidad. Gran punto dulce y excelente manejabilidad.',
         149.99, 179.99, ARRAY['https://placehold.co/600x600/16213e/e94560?text=Flash+Pro'], ARRAY[]::TEXT[], ARRAY['Azul/Negro', 'Rojo/Negro'], 40, TRUE, FALSE,
         '{"brand": "Head", "weight": "340-355g", "shape": "Teardrop", "level": "All levels"}'::jsonb),

        -- Clothing
        (v_store_id, v_cat_clothing, 'Camiseta ProNet Pro', 'camiseta-pronet-pro',
         'Camiseta técnica oficial ProNet. Tejido Dry-Fit transpirable, costuras planas y diseño ergonómico. Perfecta para entrenamientos y partidos.',
         39.99, NULL, ARRAY['https://placehold.co/600x600/533483/e94560?text=Camiseta+Pro'], ARRAY['S', 'M', 'L', 'XL', 'XXL'], ARRAY['Negro', 'Blanco', 'Azul Navy'], 100, TRUE, TRUE,
         '{"brand": "ProNet", "material": "100% Polyester Dry-Fit", "fit": "Regular"}'::jsonb),

        (v_store_id, v_cat_clothing, 'Pantalón Corto ProNet Match', 'pantalon-corto-pronet-match',
         'Pantalón corto de competición ProNet. Tejido elástico 4-way stretch, bolsillos laterales para pelotas, cintura elástica con cordón.',
         34.99, NULL, ARRAY['https://placehold.co/600x600/2b2d42/e94560?text=Short+Match'], ARRAY['S', 'M', 'L', 'XL'], ARRAY['Negro', 'Azul Navy'], 80, TRUE, FALSE,
         '{"brand": "ProNet", "material": "92% Polyester, 8% Elastane", "fit": "Athletic"}'::jsonb),

        -- Shoes
        (v_store_id, v_cat_shoes, 'Asics Gel-Padel Pro 5', 'asics-gel-padel-pro-5',
         'Zapatillas de pádel con tecnología GEL para máxima amortiguación. Suela Omni para superficies de césped artificial. Estabilidad superior.',
         129.99, 159.99, ARRAY['https://placehold.co/600x600/1a1a2e/00d2ff?text=Gel+Padel+5'], ARRAY['39', '40', '41', '42', '43', '44', '45'], ARRAY['Blanco/Azul', 'Negro/Lima'], 35, TRUE, TRUE,
         '{"brand": "Asics", "sole": "Omni", "technology": "GEL Cushioning"}'::jsonb),

        -- Accessories
        (v_store_id, v_cat_accessories, 'Overgrip ProNet Premium Pack x3', 'overgrip-pronet-premium-3pack',
         'Pack de 3 overgrips ProNet Premium. Máxima absorción y tacto seco. Duración extendida. El grip preferido por los jugadores ProNet.',
         9.99, 14.99, ARRAY['https://placehold.co/600x600/0f3460/00d2ff?text=Overgrip+x3'], ARRAY[]::TEXT[], ARRAY['Blanco', 'Negro', 'Azul'], 200, TRUE, FALSE,
         '{"brand": "ProNet", "pack_size": 3, "type": "Overgrip"}'::jsonb),

        (v_store_id, v_cat_accessories, 'Paletero ProNet Elite', 'paletero-pronet-elite',
         'Bolsa paletero premium con compartimento térmico, espacio para 3 palas, bolsillo para zapatillas y múltiples compartimentos organizadores.',
         69.99, 89.99, ARRAY['https://placehold.co/600x600/533483/00d2ff?text=Paletero+Elite'], ARRAY[]::TEXT[], ARRAY['Negro/Dorado', 'Azul Navy/Plata'], 45, TRUE, FALSE,
         '{"brand": "ProNet", "capacity": "3 rackets", "thermal": true}'::jsonb),

        -- Merch
        (v_store_id, v_cat_merch, 'Gorra ProNet Elite', 'gorra-pronet-elite',
         'Gorra oficial ProNet Elite. Diseño ajustable con cierre snapback, visera curva pre-formada, logo ProNet bordado. Protección UV 50+.',
         24.99, NULL, ARRAY['https://placehold.co/600x600/16213e/00d2ff?text=Gorra+Elite'], ARRAY['Única'], ARRAY['Negro', 'Blanco', 'Azul Navy'], 60, TRUE, TRUE,
         '{"brand": "ProNet", "type": "Snapback", "uv_protection": "50+"}'::jsonb)

        ON CONFLICT (slug) DO NOTHING;
    END IF;
END $$;

-- ============================================
-- RLS POLICIES — Shop Tables
-- ============================================

-- STORES
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Stores viewable by everyone"
    ON public.stores FOR SELECT
    USING (true);

CREATE POLICY "Store owners can insert"
    ON public.stores FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Store owners can update"
    ON public.stores FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- PRODUCT CATEGORIES
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Categories viewable by everyone"
    ON public.product_categories FOR SELECT
    USING (true);

-- PRODUCTS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active products viewable by everyone"
    ON public.products FOR SELECT
    USING (is_active = true);

CREATE POLICY "Store owners can insert products"
    ON public.products FOR INSERT
    WITH CHECK (
        auth.uid() = (SELECT owner_id FROM public.stores WHERE id = store_id)
    );

CREATE POLICY "Store owners can update products"
    ON public.products FOR UPDATE
    USING (
        auth.uid() = (SELECT owner_id FROM public.stores WHERE id = store_id)
    )
    WITH CHECK (
        auth.uid() = (SELECT owner_id FROM public.stores WHERE id = store_id)
    );

-- PRODUCT VARIANTS
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Variants viewable by everyone"
    ON public.product_variants FOR SELECT
    USING (true);

CREATE POLICY "Store owners can manage variants"
    ON public.product_variants FOR INSERT
    WITH CHECK (
        auth.uid() = (SELECT s.owner_id FROM public.stores s JOIN public.products p ON p.store_id = s.id WHERE p.id = product_id)
    );

CREATE POLICY "Store owners can update variants"
    ON public.product_variants FOR UPDATE
    USING (
        auth.uid() = (SELECT s.owner_id FROM public.stores s JOIN public.products p ON p.store_id = s.id WHERE p.id = product_id)
    );

-- CART ITEMS
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own cart"
    ON public.cart_items FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can add to own cart"
    ON public.cart_items FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own cart"
    ON public.cart_items FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can remove from own cart"
    ON public.cart_items FOR DELETE
    USING (auth.uid() = user_id);

-- ORDERS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own orders"
    ON public.orders FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create own orders"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ORDER ITEMS
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own order items"
    ON public.order_items FOR SELECT
    USING (
        order_id IN (SELECT id FROM public.orders WHERE user_id = auth.uid())
    );

-- PRODUCT REVIEWS
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Product reviews viewable by everyone"
    ON public.product_reviews FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can review products"
    ON public.product_reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own product review"
    ON public.product_reviews FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own product review"
    ON public.product_reviews FOR DELETE
    USING (auth.uid() = user_id);

-- WISHLISTS
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wishlist"
    ON public.wishlists FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can add to own wishlist"
    ON public.wishlists FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove from own wishlist"
    ON public.wishlists FOR DELETE
    USING (auth.uid() = user_id);
