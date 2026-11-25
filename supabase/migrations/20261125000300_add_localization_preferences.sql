-- DRAFT ONLY: Temmy Smart Classroom localization preferences.
-- Target: separately named temmy-smart-classroom-test project ONLY.
-- Review the complete file before applying. This file has not been executed.
-- Do not run on production. Verify the Supabase dashboard project before execution.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.teacher_profiles') IS NULL
     OR to_regclass('public.students') IS NULL
     OR to_regclass('public.classes') IS NULL
     OR to_regprocedure('public.verify_student_access_code(text)') IS NULL THEN
    RAISE EXCEPTION 'Localization preflight failed: required objects are missing';
  END IF;
  IF to_regclass('public.interface_languages') IS NOT NULL THEN
    RAISE EXCEPTION 'public.interface_languages already exists; inspect before proceeding';
  END IF;
  IF to_regprocedure('public.get_teacher_interface_language()') IS NOT NULL
     OR to_regprocedure('public.set_teacher_interface_language(text)') IS NOT NULL
     OR to_regprocedure('public.get_class_default_interface_language(uuid)') IS NOT NULL
     OR to_regprocedure('public.set_class_default_interface_language(uuid,text)') IS NOT NULL
     OR to_regprocedure('public.get_student_interface_language(text)') IS NOT NULL
     OR to_regprocedure('public.set_student_interface_language(text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'One or more proposed localization RPCs already exist';
  END IF;
END
$preflight$;

CREATE TABLE public.interface_languages (
  language_tag text PRIMARY KEY,
  native_name text NOT NULL CHECK (native_name <> '' AND native_name = btrim(native_name)),
  text_direction text NOT NULL CHECK (text_direction IN ('ltr','rtl')),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (language_tag <> '' AND language_tag = btrim(language_tag))
);

INSERT INTO public.interface_languages(language_tag,native_name,text_direction)
VALUES
 ('en','English','ltr'),
 ('ar','العربية','rtl'),
 ('fr','Français','ltr'),
 ('es','Español','ltr'),
 ('pt','Português','ltr'),
 ('hi','हिन्दी','ltr'),
 ('ur','اردو','rtl'),
 ('sw','Kiswahili','ltr'),
 ('zh-Hans','简体中文','ltr');

ALTER TABLE public.teacher_profiles
  ADD COLUMN preferred_interface_language text,
  ADD COLUMN preferred_time_zone text;
ALTER TABLE public.students
  ADD COLUMN preferred_interface_language text,
  ADD COLUMN preferred_time_zone text;
ALTER TABLE public.classes
  ADD COLUMN default_interface_language text,
  ADD COLUMN default_time_zone text;

ALTER TABLE public.teacher_profiles ADD CONSTRAINT teacher_profiles_preferred_language_fk
 FOREIGN KEY(preferred_interface_language) REFERENCES public.interface_languages(language_tag);
ALTER TABLE public.students ADD CONSTRAINT students_preferred_language_fk
 FOREIGN KEY(preferred_interface_language) REFERENCES public.interface_languages(language_tag);
ALTER TABLE public.classes ADD CONSTRAINT classes_default_language_fk
 FOREIGN KEY(default_interface_language) REFERENCES public.interface_languages(language_tag);

ALTER TABLE public.interface_languages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.interface_languages FROM PUBLIC, anon, authenticated;

-- Invoker trigger: current_user is the browser role for direct table writes,
-- but the owner role while executing an approved SECURITY DEFINER RPC.
CREATE OR REPLACE FUNCTION public.guard_localization_preference_columns()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $guard$
BEGIN
  IF current_user IN ('anon','authenticated') THEN
    IF TG_TABLE_NAME = 'teacher_profiles' THEN
      IF TG_OP = 'INSERT' THEN
        IF NEW.preferred_interface_language IS NOT NULL OR NEW.preferred_time_zone IS NOT NULL THEN
          RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
        END IF;
      ELSIF NEW.preferred_interface_language IS DISTINCT FROM OLD.preferred_interface_language
         OR NEW.preferred_time_zone IS DISTINCT FROM OLD.preferred_time_zone THEN
        RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
      END IF;
    ELSIF TG_TABLE_NAME = 'students' THEN
      IF TG_OP = 'INSERT' THEN
        IF NEW.preferred_interface_language IS NOT NULL OR NEW.preferred_time_zone IS NOT NULL THEN
          RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
        END IF;
      ELSIF NEW.preferred_interface_language IS DISTINCT FROM OLD.preferred_interface_language
         OR NEW.preferred_time_zone IS DISTINCT FROM OLD.preferred_time_zone THEN
        RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
      END IF;
    ELSIF TG_TABLE_NAME = 'classes' THEN
      IF TG_OP = 'INSERT' THEN
        IF NEW.default_interface_language IS NOT NULL OR NEW.default_time_zone IS NOT NULL THEN
          RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
        END IF;
      ELSIF NEW.default_interface_language IS DISTINCT FROM OLD.default_interface_language
         OR NEW.default_time_zone IS DISTINCT FROM OLD.default_time_zone THEN
        RAISE EXCEPTION 'Use the approved localization RPCs' USING ERRCODE='42501';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END
$guard$;
REVOKE ALL ON FUNCTION public.guard_localization_preference_columns() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER teacher_profiles_localization_guard
BEFORE INSERT OR UPDATE ON public.teacher_profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_localization_preference_columns();
CREATE TRIGGER students_localization_guard
BEFORE INSERT OR UPDATE ON public.students
FOR EACH ROW EXECUTE FUNCTION public.guard_localization_preference_columns();
CREATE TRIGGER classes_localization_guard
BEFORE INSERT OR UPDATE ON public.classes
FOR EACH ROW EXECUTE FUNCTION public.guard_localization_preference_columns();

CREATE OR REPLACE FUNCTION public.assert_enabled_interface_language(p_language_tag text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $validate$
BEGIN
  IF p_language_tag IS NULL THEN RETURN; END IF;
  IF p_language_tag = '' OR p_language_tag <> btrim(p_language_tag)
     OR NOT EXISTS (SELECT 1 FROM public.interface_languages l
                    WHERE l.language_tag=p_language_tag AND l.enabled) THEN
    RAISE EXCEPTION 'Unsupported or invalid interface language' USING ERRCODE='22023';
  END IF;
END
$validate$;
REVOKE ALL ON FUNCTION public.assert_enabled_interface_language(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_teacher_interface_language()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_language text; v_teacher uuid := auth.uid();
BEGIN
  IF v_teacher IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT preferred_interface_language INTO v_language FROM public.teacher_profiles WHERE id=v_teacher;
  IF NOT FOUND THEN RAISE EXCEPTION 'Teacher profile not found' USING ERRCODE='42501'; END IF;
  RETURN v_language;
END
$fn$;

CREATE OR REPLACE FUNCTION public.set_teacher_interface_language(p_language_tag text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_language text; v_teacher uuid := auth.uid();
BEGIN
  IF v_teacher IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  PERFORM public.assert_enabled_interface_language(p_language_tag);
  UPDATE public.teacher_profiles SET preferred_interface_language=p_language_tag, updated_at=now()
   WHERE id=v_teacher RETURNING preferred_interface_language INTO v_language;
  IF NOT FOUND THEN RAISE EXCEPTION 'Teacher profile not found' USING ERRCODE='42501'; END IF;
  RETURN v_language;
END
$fn$;

CREATE OR REPLACE FUNCTION public.get_class_default_interface_language(p_class_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_language text; v_teacher uuid := auth.uid();
BEGIN
  IF v_teacher IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  SELECT default_interface_language INTO v_language FROM public.classes
   WHERE id=p_class_id AND teacher_id=v_teacher;
  IF NOT FOUND THEN RAISE EXCEPTION 'Class not found or not owned by caller' USING ERRCODE='42501'; END IF;
  RETURN v_language;
END
$fn$;

CREATE OR REPLACE FUNCTION public.set_class_default_interface_language(p_class_id uuid,p_language_tag text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_language text; v_teacher uuid := auth.uid();
BEGIN
  IF v_teacher IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
  PERFORM public.assert_enabled_interface_language(p_language_tag);
  UPDATE public.classes SET default_interface_language=p_language_tag, updated_at=now()
   WHERE id=p_class_id AND teacher_id=v_teacher
   RETURNING default_interface_language INTO v_language;
  IF NOT FOUND THEN RAISE EXCEPTION 'Class not found or not owned by caller' USING ERRCODE='42501'; END IF;
  RETURN v_language;
END
$fn$;

CREATE OR REPLACE FUNCTION public.get_student_interface_language(p_access_code text)
RETURNS TABLE(individual_language text,class_default_language text,effective_language text,preference_source text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_student uuid; v_class uuid; v_individual text; v_default text;
BEGIN
  IF p_access_code IS NULL OR p_access_code='' THEN
    RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000';
  END IF;
  SELECT v.student_id,v.class_id INTO v_student,v_class
    FROM public.verify_student_access_code(p_access_code) v LIMIT 1;
  IF v_student IS NULL OR v_class IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000';
  END IF;
  SELECT s.preferred_interface_language,c.default_interface_language
    INTO v_individual,v_default
    FROM public.students s JOIN public.classes c ON c.id=s.class_id
   WHERE s.id=v_student AND s.class_id=v_class AND s.active IS TRUE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000'; END IF;
  individual_language := v_individual;
  class_default_language := v_default;
  IF v_individual IS NOT NULL AND EXISTS
    (SELECT 1 FROM public.interface_languages l WHERE l.language_tag=v_individual AND l.enabled) THEN
    effective_language := v_individual; preference_source := 'individual';
  ELSIF v_default IS NOT NULL AND EXISTS
    (SELECT 1 FROM public.interface_languages l WHERE l.language_tag=v_default AND l.enabled) THEN
    effective_language := v_default; preference_source := 'class';
  ELSE
    effective_language := 'en'; preference_source := 'platform';
  END IF;
  RETURN NEXT;
END
$fn$;

CREATE OR REPLACE FUNCTION public.set_student_interface_language(p_access_code text,p_language_tag text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE v_student uuid; v_class uuid; v_language text;
BEGIN
  IF p_access_code IS NULL OR p_access_code='' THEN
    RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000';
  END IF;
  PERFORM public.assert_enabled_interface_language(p_language_tag);
  SELECT v.student_id,v.class_id INTO v_student,v_class
    FROM public.verify_student_access_code(p_access_code) v LIMIT 1;
  IF v_student IS NULL OR v_class IS NULL THEN
    RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000';
  END IF;
  UPDATE public.students s SET preferred_interface_language=p_language_tag,updated_at=now()
   WHERE s.id=v_student AND s.class_id=v_class AND s.active IS TRUE
   RETURNING s.preferred_interface_language INTO v_language;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive access code' USING ERRCODE='28000'; END IF;
  RETURN v_language;
END
$fn$;

REVOKE ALL ON FUNCTION public.get_teacher_interface_language() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.set_teacher_interface_language(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_class_default_interface_language(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.set_class_default_interface_language(uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_student_interface_language(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_student_interface_language(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_teacher_interface_language() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_teacher_interface_language(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_default_interface_language(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_class_default_interface_language(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_interface_language(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_student_interface_language(text,text) TO anon,authenticated;

COMMIT;

-- Time-zone columns are included as approved nullable storage only. No time-zone
-- write/read RPC is introduced here; its API contract remains a separate decision.
-- Run post-apply catalog, privilege, ownership, and real-role behavioural tests
-- only after this entire draft has been reviewed and explicitly approved.
