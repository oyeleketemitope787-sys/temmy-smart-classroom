-- Controlled teacher read for the separate Aggregate and Spendable balances.
-- This migration is additive and must be reviewed/tested before application.

CREATE OR REPLACE FUNCTION public.get_teacher_student_point_accounts()
RETURNS TABLE (
  class_id uuid,
  student_id uuid,
  aggregate_points bigint,
  spendable_points bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    c.id AS class_id,
    s.id AS student_id,
    COALESCE(a.aggregate_points, 0)::bigint AS aggregate_points,
    COALESCE(a.spendable_points, 0)::bigint AS spendable_points
  FROM public.classes AS c
  JOIN public.students AS s
    ON s.class_id = c.id
  LEFT JOIN public.student_point_accounts AS a
    ON a.student_id = s.id
  WHERE auth.uid() IS NOT NULL
    AND c.teacher_id = auth.uid()
    AND c.active IS TRUE
    AND s.active IS TRUE
  ORDER BY c.id, s.id;
$function$;

REVOKE ALL ON FUNCTION public.get_teacher_student_point_accounts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_teacher_student_point_accounts() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_teacher_student_point_accounts() TO authenticated;

COMMENT ON FUNCTION public.get_teacher_student_point_accounts() IS
  'Returns Aggregate and Spendable point account balances only for active students in the authenticated teacher active classes.';
