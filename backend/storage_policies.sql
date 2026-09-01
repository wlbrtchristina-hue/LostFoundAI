-- ============================================================
-- storage.objects 权限修复：允许已登录用户上传/管理 images 桶文件
-- 报错现象：图片上传 403 "new row violates row level security policy"
-- 在 Supabase 控制台 → SQL Editor → New query 中粘贴执行一次即可
-- （可重复执行，幂等）
-- ============================================================

drop policy if exists "auth_upload_images" on storage.objects;
create policy "auth_upload_images" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'images');

drop policy if exists "auth_read_images" on storage.objects;
create policy "auth_read_images" on storage.objects
  for select to authenticated
  using (bucket_id = 'images');

drop policy if exists "auth_update_images" on storage.objects;
create policy "auth_update_images" on storage.objects
  for update to authenticated
  using (bucket_id = 'images');

drop policy if exists "auth_delete_images" on storage.objects;
create policy "auth_delete_images" on storage.objects
  for delete to authenticated
  using (bucket_id = 'images');
