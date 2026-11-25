-- Preserve the existing marketplace request/reward/student locks and idempotency,
-- but make affordability and deductions use Spendable Points only.
-- Aggregate Points are deliberately unchanged by marketplace purchases.

CREATE OR REPLACE FUNCTION public.purchase_marketplace_reward(
    p_request_id uuid,
    p_reward_id uuid,
    p_student_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_teacher_id uuid;
    v_reward public.marketplace_rewards%ROWTYPE;
    v_request public.marketplace_purchase_requests%ROWTYPE;
    v_student_id uuid;
    v_student_count integer;
    v_balance bigint;
    v_student_ids uuid[];
    v_result jsonb;
BEGIN
    v_teacher_id := auth.uid();

    IF v_teacher_id IS NULL THEN
        RAISE EXCEPTION 'You must be signed in as a teacher.';
    END IF;

    IF p_request_id IS NULL
       OR p_reward_id IS NULL
       OR p_student_ids IS NULL
       OR cardinality(p_student_ids) = 0 THEN
        RAISE EXCEPTION 'A request ID, reward, and at least one student are required.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(p_student_ids) AS x(id)
        WHERE x.id IS NULL
    ) OR cardinality(p_student_ids) <> (
        SELECT count(DISTINCT x.id)
        FROM unnest(p_student_ids) AS x(id)
    ) THEN
        RAISE EXCEPTION 'Student IDs must be unique and valid.';
    END IF;

    SELECT array_agg(x.id ORDER BY x.id)
    INTO v_student_ids
    FROM unnest(p_student_ids) AS x(id);

    -- Claim the request ID; concurrent retries wait for
    -- the first transaction to finish.
    INSERT INTO public.marketplace_purchase_requests
        (teacher_id, request_id, reward_id, student_ids)
    VALUES
        (v_teacher_id, p_request_id, p_reward_id, v_student_ids)
    ON CONFLICT (teacher_id, request_id) DO NOTHING;

    SELECT *
    INTO v_request
    FROM public.marketplace_purchase_requests
    WHERE teacher_id = v_teacher_id
      AND request_id = p_request_id
    FOR UPDATE;

    IF v_request.reward_id <> p_reward_id
       OR v_request.student_ids <> v_student_ids THEN
        RAISE EXCEPTION 'Request ID reused with different purchase details.';
    END IF;

    IF v_request.result IS NOT NULL THEN
        RETURN v_request.result;
    END IF;

    SELECT *
    INTO v_reward
    FROM public.marketplace_rewards
    WHERE id = p_reward_id
      AND teacher_id = v_teacher_id
      AND active = true
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reward not found, inactive, or not owned by this teacher.';
    END IF;

    IF v_reward.price IS NULL OR v_reward.price < 1 THEN
        RAISE EXCEPTION 'Reward price must be a positive number of points.';
    END IF;

    -- Lock selected students in a consistent order.
    PERFORM s.id
    FROM public.students AS s
    JOIN public.classes AS c ON c.id = s.class_id
    WHERE s.id = ANY(v_student_ids)
      AND s.active = true
      AND c.active = true
      AND c.teacher_id = v_teacher_id
    ORDER BY s.id
    FOR UPDATE OF s;

    SELECT count(*)
    INTO v_student_count
    FROM public.students AS s
    JOIN public.classes AS c ON c.id = s.class_id
    WHERE s.id = ANY(v_student_ids)
      AND s.active = true
      AND c.active = true
      AND c.teacher_id = v_teacher_id;

    IF v_student_count <> cardinality(v_student_ids) THEN
        RAISE EXCEPTION 'One or more students are inactive or not in your classes.';
    END IF;

    -- Ensure an account exists even for a student created after the
    -- initial backfill. Derive any missing account from that student's
    -- own legacy ledger rows; never infer from another student's balance.
    INSERT INTO public.student_point_accounts (
        student_id, aggregate_points, spendable_points
    )
    SELECT
        s.id,
        COALESCE(SUM(pt.points) FILTER (
            WHERE pt.action_type IS DISTINCT FROM 'marketplace_purchase'
        ), 0)::bigint,
        COALESCE(SUM(pt.points), 0)::bigint
    FROM public.students AS s
    LEFT JOIN public.point_transactions AS pt
      ON pt.student_id = s.id
    WHERE s.id = ANY(v_student_ids)
    GROUP BY s.id
    ORDER BY s.id
    ON CONFLICT (student_id) DO NOTHING;

    -- Lock account rows deterministically before checking and changing
    -- Spendable Points. Aggregate Points are not touched by purchases.
    PERFORM a.student_id
    FROM public.student_point_accounts AS a
    WHERE a.student_id = ANY(v_student_ids)
    ORDER BY a.student_id
    FOR UPDATE;

    -- Validate every Spendable balance before inserting any purchase.
    FOREACH v_student_id IN ARRAY v_student_ids LOOP
        SELECT a.spendable_points
        INTO v_balance
        FROM public.student_point_accounts AS a
        WHERE a.student_id = v_student_id;

        IF NOT FOUND OR v_balance < v_reward.price THEN
            RAISE EXCEPTION
                'Insufficient Spendable Points for at least one selected student. No purchase completed.';
        END IF;
    END LOOP;

    FOREACH v_student_id IN ARRAY v_student_ids LOOP
        INSERT INTO public.point_transactions (
            student_id, teacher_id, points,
            action_name, action_type, reason, source
        )
        VALUES (
            v_student_id, v_teacher_id, -v_reward.price,
            'Marketplace Purchase: ' || v_reward.name,
            'marketplace_purchase',
            'Marketplace Purchase: ' || v_reward.name,
            'teacher'
        );

        INSERT INTO public.purchases (
            student_id, teacher_id, reward_id,
            reward_name, points_spent
        )
        VALUES (
            v_student_id, v_teacher_id, v_reward.id,
            v_reward.name, v_reward.price
        );

        UPDATE public.student_point_accounts
        SET spendable_points = spendable_points - v_reward.price,
            updated_at = now()
        WHERE student_id = v_student_id;
    END LOOP;

    v_result := jsonb_build_object(
        'success', true,
        'request_id', p_request_id,
        'reward_id', v_reward.id,
        'reward_name', v_reward.name,
        'points_spent_per_student', v_reward.price,
        'student_ids', to_jsonb(v_student_ids),
        'student_count', cardinality(v_student_ids)
    );

    UPDATE public.marketplace_purchase_requests
    SET result = v_result
    WHERE teacher_id = v_teacher_id
      AND request_id = p_request_id;

    RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.purchase_marketplace_reward(uuid, uuid, uuid[]) IS
  'Processes idempotent teacher marketplace purchases using Spendable Points only; Aggregate Points are unchanged.';
