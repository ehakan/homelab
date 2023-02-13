import { Chart, Helm, JsonPatch } from "cdk8s";
import { Construct } from "constructs";

export interface OnePasswordProps {
  releaseName?: string,
  namespace?: string,
  version?: string,
}

export class OnePassword extends Construct {
  public readonly releaseName: string;
  public readonly namespace: string;
  public readonly version: string;
  public readonly helmChart: Helm;
  constructor(scope: Construct, id: string, props: OnePasswordProps = {}) {
    super(scope, id);

    this.releaseName = props.releaseName ?? "onepassword";
    this.namespace = props.namespace ?? Chart.of(this).namespace ?? "onepassword";
    this.version = props.version ?? "1.10.0";

    this.helmChart = new Helm(this, "external-secrets-helm", {
      chart: "connect",
      repo: "https://1password.github.io/connect-helm-charts/",
      releaseName: this.releaseName,
      namespace: this.namespace,
      version: this.version,
      helmFlags: [
        "--create-namespace",
      ],
    });

    for (let i = 0; i < this.helmChart.apiObjects.length; i++) {
      const apiObject = this.helmChart.apiObjects[i];
      if (apiObject.metadata.name === `${this.helmChart.releaseName}-health-check`) {
        apiObject.addJsonPatch(JsonPatch.remove("/"));
      }
    }
  }

}
