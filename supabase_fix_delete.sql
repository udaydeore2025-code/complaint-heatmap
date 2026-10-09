-- ==============================================================================
-- CivicConnect: Fix Complaint Deletion in Supabase
-- Run this script in your Supabase Project > SQL Editor > New Query > RUN
-- ==============================================================================

-- 1. Helper function: case-insensitive admin check
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND LOWER(role) = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Stored Procedure for Cascading Deletion (Security Definer)
-- Cleanly removes votes, confirmations, updates, and the complaint itself
CREATE OR REPLACE FUNCTION public.delete_complaint(
    complaint_id UUID DEFAULT NULL,
    target_complaint_id UUID DEFAULT NULL
)
RETURNS boolean AS $$
DECLARE
    v_target_id UUID;
    v_user_id UUID;
    v_role TEXT;
BEGIN
    v_target_id := COALESCE(complaint_id, target_complaint_id);
    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'No complaint ID provided';
    END IF;

    -- Fetch complaint creator
    SELECT user_id INTO v_user_id
    FROM public.complaints
    WHERE id = v_target_id;

    -- If already deleted or not found, return true
    IF v_user_id IS NULL THEN
        RETURN true;
    END IF;

    -- Fetch caller role
    SELECT role INTO v_role
    FROM public.profiles
    WHERE id = auth.uid();

    -- Check authorization: creator or municipal admin
    IF auth.uid() != v_user_id AND LOWER(COALESCE(v_role, '')) != 'admin' THEN
        RAISE EXCEPTION 'Not authorized to delete this complaint';
    END IF;

    -- Delete all child records cleanly
    DELETE FROM public.votes WHERE public.votes.complaint_id = v_target_id;
    DELETE FROM public.complaint_confirmations WHERE public.complaint_confirmations.complaint_id = v_target_id;
    DELETE FROM public.complaint_updates WHERE public.complaint_updates.complaint_id = v_target_id;
    DELETE FROM public.complaints WHERE id = v_target_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execution to authenticated users, anon, and service roles
GRANT EXECUTE ON FUNCTION public.delete_complaint(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_complaint(UUID, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.delete_complaint(UUID, UUID) TO service_role;

-- 3. Complaints DELETE policy
DROP POLICY IF EXISTS "Users can delete own complaints or admins can delete any complaint" ON public.complaints;
DROP POLICY IF EXISTS "Users can delete own complaints" ON public.complaints;
CREATE POLICY "Users can delete own complaints or admins can delete any complaint"
ON public.complaints FOR DELETE
TO authenticated
USING (
  auth.uid() = user_id 
  OR public.is_admin()
);

-- 4. Child tables DELETE policies
DROP POLICY IF EXISTS "Users can delete their own vote or complaint owner can delete" ON public.votes;
DROP POLICY IF EXISTS "Users can delete their own vote" ON public.votes;
CREATE POLICY "Users can delete their own vote or complaint owner can delete"
ON public.votes FOR DELETE
TO authenticated
USING (
  auth.uid() = user_id 
  OR auth.uid() IN (SELECT user_id FROM public.complaints WHERE id = complaint_id)
  OR public.is_admin()
);

DROP POLICY IF EXISTS "Users can remove confirmation or complaint owner can delete" ON public.complaint_confirmations;
DROP POLICY IF EXISTS "Users can remove their confirmation" ON public.complaint_confirmations;
CREATE POLICY "Users can remove confirmation or complaint owner can delete"
ON public.complaint_confirmations FOR DELETE
TO authenticated
USING (
  auth.uid() = user_id 
  OR auth.uid() IN (SELECT user_id FROM public.complaints WHERE id = complaint_id)
  OR public.is_admin()
);

DROP POLICY IF EXISTS "Complaint updates can be deleted by admins or complaint owner" ON public.complaint_updates;
CREATE POLICY "Complaint updates can be deleted by admins or complaint owner"
ON public.complaint_updates FOR DELETE
TO authenticated
USING (
  auth.uid() IN (SELECT user_id FROM public.complaints WHERE id = complaint_id)
  OR public.is_admin()
);

