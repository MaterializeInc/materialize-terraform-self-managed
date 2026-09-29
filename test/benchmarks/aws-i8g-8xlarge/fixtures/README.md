# Fixtures for reproducing the comparison

This run was initialised with `--persist-backend ceph`, so Ceph is the injected
store and Materialize's persist backend. The other two were added around it.

## `warm-ceph-pool.yaml`

Apply after the storage pool exists and before the Ceph resources, and wait for
all four pods. Rook pins each daemon to a node by hostname, and Karpenter will
not provision a node for a pod that already names one, so the pool has to
exist first.

It lives in `default`, not `rook-ceph`. When Ceph is the injected store the
module creates `rook-ceph` itself, and a namespace made beforehand fails that
apply with "already exists".

## `second-store-rustfs.tf.example`

Copy into the run directory to add rustfs on the same four nodes as Ceph. It
uses the portable module rather than the AWS wrapper, because the wrapper brings
its own node pool, and a second pool of `i8g.8xlarge` would both change the
hardware under comparison and exhaust a subnet: the VPC CNI holds 30 to 60
addresses per node at this size.

## S3

Needs no store of its own. Benchmark the run's bucket with `--blob-uri
s3://<bucket>/<prefix>?region=<region>`, `--service-account main` and
`--namespace materialize-environment`, so the Job assumes the IRSA role persist
itself uses.

## Tearing down

`terraform destroy` stalls on the Ceph object store user, and only a person can
clear it:

- RGW will not delete a user that still owns a bucket, and the module's bucket
  is created by a Job through the S3 API, so nothing removes it. Empty it first,
  with `radosgw-admin bucket rm --bucket=materialize --purge-objects` from the
  operator pod.
- Cluster DNS can be destroyed before Ceph, after which Rook cannot reach the
  gateway by name and its finalizers never complete. Once that has happened,
  removing the Ceph resources' finalizers is the only way forward.

Afterwards run `terraform-tests purge`: it found six EBS volumes Terraform had
left behind. Check its output for errors rather than trusting its last line,
which reports success even when every call failed.
