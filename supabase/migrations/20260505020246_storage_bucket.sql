INSERT INTO storage.buckets (id, name, public)
VALUES ('food-photos', 'food-photos', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "food_photos_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'food-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "food_photos_select" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'food-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "food_photos_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'food-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
