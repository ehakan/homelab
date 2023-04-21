import { Include, JsonPatch } from "cdk8s";
import { Construct } from "constructs";
import { Container, Volume } from "../../imports/k8s";

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

  /**
  * Patch ArgoCD installation manifest to include a Sidecar Config Management Plugin
  */
  public addSidecarPlugin(pluginName: string, pluginImage: string) {
    if (!pluginName) {
      throw new Error(`Invalid pluginName: ${pluginName === "" ? "<empty>" : pluginName}`);
    }
    if (!pluginImage) {
      throw new Error(`Invalid pluginImage: ${pluginImage === "" ? "<empty>" : pluginImage}`);
    }

    // We need to patch this deployment with our sidecar plugin
    const patchTargetName = "argocd-repo-server";
    const repoServerDeployment = this.included.apiObjects.find((apiObject) =>
      apiObject.kind === "Deployment" && apiObject.name === patchTargetName
    );
    if (!repoServerDeployment) {
      throw new Error(`Could not find Deployment with the name ${patchTargetName}`);
    }

    let sidecarContainer: Container = {
      name: pluginName,
      image: pluginImage,
      command: [
        // this entrypoint comes from the mount "var-files", mounted by argocd
        "/var/run/argocd/argocd-cmp-server",
      ],
      securityContext: {
        runAsNonRoot: true,
        runAsUser: 999,
      },
      volumeMounts: [
        {
          // Includes the "argocd-cmp-server" entrypoint
          name: "var-files",
          mountPath: "/var/run/argocd",
        },
        {
          name: "plugins",
          mountPath: "/home/argocd/cmp-server/plugins",
        },
        {
          // Separate tmp volume from the repo-server container for mitigating path traversal attacks
          name: "cmp-tmp",
          mountPath: "/tmp",
        },
      ],
    };

    repoServerDeployment?.addJsonPatch(JsonPatch.add(
      "/spec/template/spec/containers/-",
      sidecarContainer,
    ));

    let volumes: Volume[] = [
      {
        name: "cmp-tmp",
        emptyDir: {},
      },
    ];

    repoServerDeployment?.addJsonPatch(JsonPatch.add(
      "/spec/template/spec/volumes",
      volumes,
    ));
  };

  public patchConfigMap(...ops: JsonPatch[]) {
    const configMap = this.included.apiObjects.find(obj => (obj.name === "argocd-cm" && obj.kind === "ConfigMap"));
    if (!configMap) {
      throw new Error("Could not find ConfigMap 'argocd-cm' to patch");
    }

    configMap.addJsonPatch(...ops);
  };
}

