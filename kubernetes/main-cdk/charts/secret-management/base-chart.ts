import { Construct } from "constructs";
import { Chart, ChartProps } from "cdk8s";

import { ExternalSecrets } from "../../lib/secret-management/external-secrets";
import { OnePassword } from "../../lib/secret-management/onepassword";

/**
 * Required services and helm charts for Secret Management
 *
 * Installs `external-secrets` and `onepassword-connect`
 *
 * This chart requires a secret the following secret in the same namespace
 *
 * - `op-credentials."1password-credential.json"`, Base64 encoded 1Password Credentials file contents
 */
export class SecretManagementBaseChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {
    namespace: "secret-management",
  }) {
    super(scope, id, props);

    new ExternalSecrets(this, "external-secrets", {
      namespace: props.namespace,
    });
    new OnePassword(this, "onepassword", {
      namespace: props.namespace,
    });
  }
}
