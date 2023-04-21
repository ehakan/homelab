import { App, Chart, ChartProps, YamlOutputType } from 'cdk8s';
import { ArgoCdChart } from './charts/gitops/argocd-chart';
import { SecretManagementBaseChart } from './charts/secret-management/base-chart';
import { SecretManagementResourcesChart } from "./charts/secret-management/resources-chart";
import { AppOfAppsChart } from "./charts/gitops/appofapps-chart";

const app = new App({
  yamlOutputType: YamlOutputType.FILE_PER_CHART,
  recordConstructMetadata: true,
});
const secretManagementResources = new SecretManagementResourcesChart(app, 'secret-management-resources');
const secretManagementBase = new SecretManagementBaseChart(app, 'secret-management-base');
secretManagementResources.addDependency(secretManagementBase);
const argocd = new ArgoCdChart(app, 'argocd');

const appofapps = new AppOfAppsChart(app, 'appofapps');

console.log(secretManagementResources.toString());

app.synth();
