import { Chart, Testing } from "cdk8s";
import { ArgoCd } from "../../lib/gitops/argocd";
import { Container } from "../../imports/k8s";

describe("with sidecar config management plugins", () => {
  let chart: Chart;
  let argoCd: ArgoCd;
  const pluginName = "plugin-name-foo";
  const pluginImage = "plugin-image-bar";
  let manifests: any[];

  beforeAll(() => {
    chart = Testing.chart();
    argoCd = new ArgoCd(chart, "argocd", {
      version: "2.6.6",
    });
    argoCd.addSidecarPlugin(pluginName, pluginImage);
    manifests = Testing.synth(chart);
  });

  test("manifests has correct argocd-repo-server deployment", () => {
    expect(manifests).toBeDefined();
    expect(manifests).not.toHaveLength(0);

    const repoServerDeployment = manifests.find((manifest) =>
      manifest.apiVersion === "apps/v1" &&
      manifest.kind === "Deployment" &&
      manifest.metadata.name === "argocd-repo-server"
    );
    expect(repoServerDeployment).toBeDefined();

    expect(repoServerDeployment.spec.template.spec.containers).toHaveLength(2);
    const sidecarContainer: Container = repoServerDeployment.spec.template.spec.containers.find((container: Container) =>
      container.name === pluginName
    );
    expect(sidecarContainer).toBeDefined();
    expect(sidecarContainer.image).toBe(pluginImage);

    expect(sidecarContainer.securityContext).toStrictEqual({
      runAsNonRoot: true,
      runAsUser: 999,
    });

    // Sidecar container must have this entrypoint that have been mounted through `/var/run/argocd`
    const entrypoint = "/var/run/argocd/argocd-cmp-server";
    expect(sidecarContainer.command).toBeDefined();
    expect(sidecarContainer.command).not.toHaveLength(0);
    expect(sidecarContainer.command?.[0]).toBe(entrypoint);

    // Sidecar container must mount `/var/run/argocd` to get the entrypoint `/var/run/argocd/argocd-cmp-server`
    expect(sidecarContainer.volumeMounts).toContainEqual({
      name: "var-files",
      mountPath: "/var/run/argocd",
    });
    expect(sidecarContainer.volumeMounts).toContainEqual({
      name: "plugins",
      mountPath: "/home/argocd/cmp-server/plugins",
    });
  })
});
