import { Construct } from "constructs";
import { Chart, ChartProps } from "cdk8s";
import * as kplus from "cdk8s-plus-25"

import { OnePasswordClusterSecretStore } from "../../lib/secret-management/op-cluster-secret-store";

/**
 * Required services and helm charts for Secret Management
 *
 * Installs `external-secrets` and `onepassword-connect`
 *
 * This chart requires a secret the following secret in the same namespace
 *
 * - `op-credentials."1password-credential.json"`, Base64 encoded 1Password Credentials file contents
 */
export class SecretManagementResourcesChart extends Chart {
    constructor(scope: Construct, id: string, props: ChartProps = {
        namespace: "secret-management",
    }) {
        super(scope, id, props);

        const accessTokenSecret = kplus.Secret.fromSecretName(this, "access-token", "op-access-token");
        new OnePasswordClusterSecretStore(this, "cluster-secret-store", {
            secret: accessTokenSecret,
            namespace: props.namespace,
        });
    }
}
