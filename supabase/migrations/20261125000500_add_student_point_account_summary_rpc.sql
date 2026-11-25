-- Secure student point-account summary using the existing access-code verification path.
-- Students receive only their own two balances; direct account-table access remains revoked.

CREATE OR REPLACE FUNCTION public.get_student_point_account_summary(p_access_code text)
RETURNS TABLE (
  aggregate_points bigint,
  spendable_points bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    COALESCE(a.aggregate_points, 0)::bigint AS aggregate_points,
    COALESCE(a.spendable_points, 0)::bigint AS spendable_points
  FROM public.verify_student_access_code(p_access_code) AS v
  LEFT JOIN public.student_point_accounts AS a
    ON a.student_id = v.student_id
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_student_point_account_summary(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_student_point_account_summary(text) FROM authenticated;
REVOKE ALL ON FUNCTION public.get_student_point_account_summary(text) FROM anon;

-- Student Portal uses the publishable/anonymous Supabase client and access-code verification.
GRANT EXECUTE ON FUNCTION public.get_student_point_account_summary(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_student_point_account_summary(text) TO authenticated;

COMMENT ON FUNCTION public.get_student_point_account_summary(text) IS
  'Returns only Aggregate and Spendable point balances for the active student verified by the supplied student access code.';
