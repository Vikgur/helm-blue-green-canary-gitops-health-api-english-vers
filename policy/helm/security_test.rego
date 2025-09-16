package helm

test_no_privileged {
  not security.deny with input as {
    "kind": "Pod",
    "spec": {"containers": [{"name": "app", "securityContext": {"privileged": true}}]}
  }
}

test_has_limits {
  count(security.deny with input as {
    "kind": "Pod",
    "spec": {"containers": [{"name": "app"}]}
  }) == 1
}
