package devsecops.release

import rego.v1

default allow := false

allow if {
    input.tests_passed == true
    input.sast_passed == true
    input.dependencies_passed == true
    input.secrets_passed == true
    input.container_passed == true
    input.iac_passed == true
    input.policy_tests_passed == true
}
