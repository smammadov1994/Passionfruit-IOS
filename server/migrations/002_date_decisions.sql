-- Each participant's private answer, kept so pairing can rank by likely mutual interest.
-- NULL when the date ended before the yes/no screen. No answer by the deadline is stored as 'no'.

ALTER TABLE dates
  ADD COLUMN decision_a text CHECK (decision_a IS NULL OR decision_a IN ('yes', 'no')),
  ADD COLUMN decision_b text CHECK (decision_b IS NULL OR decision_b IN ('yes', 'no'));
