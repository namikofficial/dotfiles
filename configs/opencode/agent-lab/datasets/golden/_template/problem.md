# Replace with the verbatim user-visible problem statement.
#
# Example:
# User reports: after switching workspace, the parts list still shows parts from
# the previous workspace. Reproduces 100% of the time in Chrome/Firefox/Safari.
# Affects ~12% of users based on session analytics.
#
# Acceptance criteria:
# 1. Switching workspace refreshes the parts list within 1 second
# 2. No console errors during the switch
# 3. Filter state preserved across workspace switch
# 4. Bulk selection cleared after workspace switch
# 5. Regression test added that fails before fix and passes after
