import { Chart, ChartProps, JsonPatch } from "cdk8s";
import { Construct } from "constructs";

import { ArgoCd } from "../../lib/gitops/argocd";
import { PublicRepository } from "../../lib/gitops/public-repository";


export class ArgoCdChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {
    namespace: "argocd",
  }) {
    super(scope, id, props);

    const argocd = new ArgoCd(this, 'argocd');

    // TODO: Setup all declarative configuration options in ArgoCD construct props
    const argocdConfigMap = argocd.included.apiObjects.find(obj => (obj.name === "argocd-cm" && obj.kind === "ConfigMap"));
    if (!argocdConfigMap) {
      throw new Error("Could not find ConfigMap 'argocd-cm' to patch");
    }
    argocdConfigMap.addJsonPatch(JsonPatch.add("/data", { "kustomize.buildOptions": "--enable-helm" }));

    new PublicRepository(this, 'homelab-repository', {
      repositoryDefinition: {
        type: "git",
        url: "https://github.com/ehakan/homelab",
      },
    });
  }
}
