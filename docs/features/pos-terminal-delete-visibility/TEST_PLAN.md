# Test plan — pos-terminal-delete-visibility

| AC | Test | Kind |
|---|---|---|
| AC-1 | `PosProvisioningTest::test_the_terminal_list_says_which_terminals_have_money_history`; `TenantCreationTest::test_the_tenant_terminal_list_says_which_terminals_have_money_history` | API feature |
| AC-2 | the two above and `PosProvisioningTest::test_the_flag_agrees_with_what_delete_answers` | API feature |
| AC-3 | `PosProvisioningTest::test_the_flag_costs_the_same_queries_for_one_terminal_or_many` | API feature |
| AC-4 | `PosProvisioningTest::test_provisioning_response_does_not_carry_the_flag` | API feature |
| AC-5, AC-6 | gap: no JS test framework; a person checks both pages, en and ar | manual |
