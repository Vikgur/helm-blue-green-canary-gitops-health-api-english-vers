package helm.security

# Launching privileged containers is prohibited
deny[msg] {
  input.kind == "Pod"
  c := input.spec.containers[_]
  c.securityContext.privileged == true
  msg := sprintf("Privileged container is forbidden: %s", [c.name])
}

# Each container must have resource limits set
deny[msg] {
  input.kind == "Pod"
  c := input.spec.containers[_]
  not c.resources.limits
  msg := sprintf("Missing limits for container %s", [c.name])
}
