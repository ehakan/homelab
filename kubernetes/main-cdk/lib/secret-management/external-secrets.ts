import { Chart, Helm } from "cdk8s";
import { Construct } from "constructs";

export interface ExternalSecretsProps {
  releaseName?: string,
  namespace?: string,
  version?: string,
}

export class ExternalSecrets extends Construct {
  public readonly releaseName: string;
  public readonly namespace: string;
  public readonly version: string;
  public readonly helmChart: Helm;

  constructor(scope: Construct, id: string, props: ExternalSecretsProps = {}) {
    super(scope, id);

    this.releaseName = props.releaseName ?? "external-secrets";
    this.namespace = props.namespace ?? Chart.of(this).namespace ?? "external-secrets";
    this.version = props.version ?? "0.7.2";

    this.helmChart = new Helm(this, "external-secrets-helm", {
      chart: "external-secrets",
      repo: "https://charts.external-secrets.io",
      releaseName: this.releaseName,
      namespace: this.namespace,
      version: this.version,
      helmFlags: [
        "--create-namespace",
      ],
    });
  }
}
