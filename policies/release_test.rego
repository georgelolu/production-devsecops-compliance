package devsecops.release_test

import rego.v1
import data.devsecops.release

test_release_allowed_when_all_controls_pass if {
    release.allow with input as {
        "tests_passed": true,
        "sast_passed": true,
        "dependencies_passed": true,
        "secrets_passed": true,
        "container_passed": true,
        "iac_passed": true,
        "policy_tests_passed": true
    }
}

test_release_denied_when_container_scan_fails if {
    not release.allow with input as {
        "tests_passed": true,
        "sast_passed": true,
        "dependencies_passed": true,
        "secrets_passed": true,
        "container_passed": false,
        "iac_passed": true,
        "policy_tests_passed": true
    }
}

test_release_denied_when_secrets_check_fails if {
    not release.allow with input as {
        "tests_passed": true,
        "sast_passed": true,
        "dependencies_passed": true,
        "secrets_passed": false,
        "container_passed": true,
        "iac_passed": true,
        "policy_tests_passed": true
    }
}
