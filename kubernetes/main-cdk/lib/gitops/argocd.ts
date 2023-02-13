import { Include } from "cdk8s";
import { Construct } from "constructs";

export interface ArgoCDProps {
  version?: string,
}

export class ArgoCd extends Construct {
  public readonly version: string;
  public readonly included: Include;

  constructor(scope: Construct, id: string, props: ArgoCDProps = {}) {
    super(scope, id);

    this.version = props.version ?? "0.6.1";

    // TODO: Allow optional high-availability and/or core installs
    const url = `https://raw.githubusercontent.com/argoproj/argo-cd/v${this.version}/manifests/install.yaml`
    this.included = new Include(this, 'argocd-installation', {
      url,
    });

  }
}
