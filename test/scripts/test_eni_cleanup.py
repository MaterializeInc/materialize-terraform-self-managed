"""Run the real cleanup script against an isolated AWS CLI double.

Requires jmespath==1.0.1, the query language used by the AWS CLI.
"""

import fnmatch
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import jmespath


def fake_aws():
    state_path = Path(os.environ["ENI_TEST_STATE"])
    state = json.loads(state_path.read_text())
    args = sys.argv[1:]
    assert args[:1] == ["ec2"], args
    assert args[args.index("--region") + 1] == "us-east-1", args
    profile = args[args.index("--profile") + 1] if "--profile" in args else ""
    assert profile == state["profile"], args
    if args[1] == "describe-network-interfaces":
        if state.get("list_error"):
            sys.exit("UnauthorizedOperation")
        filters = args[args.index("--filters") + 1 : args.index("--query")]
        interfaces = state["interfaces"]
        for item in filters:
            name, values = item.removeprefix("Name=").split(",Values=", 1)

            def matches(eni):
                tags = {tag["Key"]: tag["Value"] for tag in eni["TagSet"]}
                if name == "group-id":
                    actual = [group["GroupId"] for group in eni["Groups"]]
                elif name == "status":
                    actual = [eni["Status"]]
                elif name == "description":
                    actual = [eni["Description"]]
                elif name == "tag-key":
                    actual = list(tags)
                elif name.startswith("tag:"):
                    actual = [tags[name[4:]]] if name[4:] in tags else []
                else:
                    raise AssertionError(f"Unexpected filter: {name}")
                return any(
                    fnmatch.fnmatchcase(value, pattern)
                    for value in actual
                    for pattern in values.split(",")
                )

            interfaces = [eni for eni in interfaces if matches(eni)]
        result = jmespath.search(
            args[args.index("--query") + 1], {"NetworkInterfaces": interfaces}
        )
        print("\t".join(result))
    elif args[1] == "delete-network-interface":
        eni_id = args[args.index("--network-interface-id") + 1]
        state["deletes"].append(eni_id)
        state["interfaces"] = [
            eni for eni in state["interfaces"] if eni["NetworkInterfaceId"] != eni_id
        ]
        state_path.write_text(json.dumps(state))
        if state.get("delete_error"):
            sys.exit(state["delete_error"])
    else:
        raise AssertionError(f"Unexpected AWS operation: {args}")


def interface(eni_id, tags, *, status="available", group="sg-test", cni=True):
    return {
        "NetworkInterfaceId": eni_id,
        "Status": status,
        "Groups": [{"GroupId": group}],
        "Description": "aws-K8S-i-test" if cni else "unrelated interface",
        "TagSet": [{"Key": key, "Value": value} for key, value in tags.items()],
    }


class EniCleanupTest(unittest.TestCase):
    def run_cleanup(self, interfaces, *, profile="", **errors):
        script = (
            Path(__file__).resolve().parents[2]
            / "aws/modules/eks-node-group/scripts/eni-cleanup.sh"
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            aws = root / "aws"
            aws.write_text(f"#!{sys.executable}\n" + Path(__file__).read_text())
            aws.chmod(0o755)
            state = root / "state.json"
            state.write_text(
                json.dumps(
                    {
                        "interfaces": interfaces,
                        "deletes": [],
                        "profile": profile,
                        **errors,
                    }
                )
            )
            result = subprocess.run(
                ["sh", str(script)],
                env={
                    "PATH": f"{root}:/usr/bin:/bin",
                    "ENI_TEST_STATE": str(state),
                    "SG_ID": "sg-test",
                    "REGION": "us-east-1",
                    "CLUSTER_NAME": "test-cluster",
                    "NODE_GROUP_PREFIX": "test-base",
                    "PROFILE": profile,
                },
                capture_output=True,
                text=True,
                timeout=10,
            )
            return result, json.loads(state.read_text())["deletes"]

    def test_selects_only_detached_owned_interfaces(self):
        node = {"node.k8s.amazonaws.com/instance_id": "i-test"}
        cluster = {"cluster.k8s.amazonaws.com/name": "test-cluster"}
        eks = {
            "eks:cluster-name": "test-cluster",
            "eks:nodegroup-name": "test-base-123",
        }
        interfaces = [
            interface("eni-eks", eks),
            interface("eni-cluster", cluster),
            # Shape observed in the failed CI deployment: no cluster tag.
            interface(
                "eni-node",
                {**node, "node.k8s.amazonaws.com/createdAt": "2026-01-01T00:00:00Z"},
            ),
            interface("eni-both", {**node, **cluster}),
            interface("eni-attached", node, status="in-use"),
            interface("eni-other-group", node, group="sg-other"),
            interface("eni-untagged", {}),
            interface("eni-not-cni", node, cni=False),
            interface(
                "eni-other-cluster", {**node, "cluster.k8s.amazonaws.com/name": "other"}
            ),
            interface("eni-other-nodegroup", {**eks, "eks:nodegroup-name": "other"}),
        ]
        for profile in ("", "test-profile"):
            with self.subTest(profile=profile):
                result, deletes = self.run_cleanup(interfaces, profile=profile)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertCountEqual(
                    deletes, ["eni-eks", "eni-cluster", "eni-node", "eni-both"]
                )

    def test_empty_result(self):
        result, deletes = self.run_cleanup([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deletes, [])

    def test_delete_races_and_errors(self):
        for error, success in (
            ("InvalidNetworkInterfaceID.NotFound", True),
            ("UnauthorizedOperation", False),
            ("InvalidParameterValue: interface is in use", False),
        ):
            with self.subTest(error=error):
                result, deletes = self.run_cleanup(
                    [
                        interface(
                            "eni-node", {"node.k8s.amazonaws.com/instance_id": "i-test"}
                        )
                    ],
                    delete_error=error,
                )
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(deletes, ["eni-node"])

    def test_list_error_does_not_delete(self):
        result, deletes = self.run_cleanup([], list_error=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(deletes, [])


if __name__ == "__main__":
    if Path(sys.argv[0]).name == "aws":
        fake_aws()
    else:
        unittest.main()
