-- ============================================
-- PadelApp — Supabase Storage Buckets
-- Migration: 004_storage
-- ============================================

-- Create storage buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
    ('posts', 'posts', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/webm']),
    ('courts', 'courts', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('chat', 'chat', false, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'audio/mpeg', 'audio/webm'])
ON CONFLICT (id) DO NOTHING;

-- Storage policies: avatars
CREATE POLICY "Avatar images are publicly accessible" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Users can upload their own avatar" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
CREATE POLICY "Users can update their own avatar" ON storage.objects FOR UPDATE USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
CREATE POLICY "Users can delete their own avatar" ON storage.objects FOR DELETE USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Storage policies: posts media
CREATE POLICY "Post media is publicly accessible" ON storage.objects FOR SELECT USING (bucket_id = 'posts');
CREATE POLICY "Authenticated users can upload post media" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'posts' AND auth.uid()::text = (storage.foldername(name))[1]);
CREATE POLICY "Users can delete their own post media" ON storage.objects FOR DELETE USING (bucket_id = 'posts' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Storage policies: courts
CREATE POLICY "Court images are publicly accessible" ON storage.objects FOR SELECT USING (bucket_id = 'courts');
CREATE POLICY "Court owners can upload images" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'courts' AND auth.role() = 'authenticated');

-- Storage policies: chat (private)
CREATE POLICY "Chat participants can view media" ON storage.objects FOR SELECT USING (bucket_id = 'chat' AND auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can upload chat media" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'chat' AND auth.role() = 'authenticated');
