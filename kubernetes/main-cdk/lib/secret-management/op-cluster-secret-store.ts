import { Construct } from "constructs";
import { Chart } from "cdk8s";

import { ClusterSecretStoreV1Beta1 } from "../../imports/external-secrets.io";
import * as kplus from "cdk8s-plus-25";

export interface OnePasswordClusterSecretStoreProps {
  /**
   * 1Passowrd Access Token Secret
   *
   * Used by external-secrets to connect to onepassword-connect
   */
  secret: kplus.ISecret;

  namespace?: string;
}

/**
 * ClusterSecretStore for 1Password Connection
 */
export class OnePasswordClusterSecretStore extends Construct {
  constructor(scope: Construct, id: string, props: OnePasswordClusterSecretStoreProps) {
    super(scope, id);

    new ClusterSecretStoreV1Beta1(this, "op-cluster-secret-store", {
      spec: {
        provider: {
          onepassword: {
            // TODO: pull this information from OnePassword construct
            connectHost: "http://onepassword-connect:8080",
            vaults: {
              "homelab": 1,
            },
            auth: {
              secretRef: {
                connectTokenSecretRef: {
                  namespace: props.namespace ?? Chart.of(this).namespace,
                  name: props.secret.name,
                  key: "token",
                },
              },
            },
          },
        },
      },
    });
  }
}