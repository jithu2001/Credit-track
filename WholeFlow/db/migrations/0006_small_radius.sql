-- WholeFlow — allow shop check-in radii down to 5 m (was 20 m) for small shops.
--
-- Additive and safe on the live database: only the range check on
-- shop_locations.radius_m is widened; existing pins are unchanged.
-- Phone GPS is usually off by 5–20 m, so the app warns that radii under 20 m
-- may refuse staff who are inside the shop.
--
-- Applied by the WholeFlow server to every business (scripts/migrate.sh, or the
-- admin app → Settings → Update all businesses).

begin;

alter table public.shop_locations drop constraint shop_locations_radius_m_check;
alter table public.shop_locations add constraint shop_locations_radius_m_check check (radius_m between 5 and 2000);

commit;
