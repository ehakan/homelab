import * as cdk8s from "cdk8s";
import { Construct } from "constructs";

export class AppOfAppsChart extends cdk8s.Chart {
  constructor(scope: Construct, id: string, props: cdk8s.ChartProps = {
    namespace: "argocd",
  }) {
    super(scope, id, props);

    if (!(scope instanceof cdk8s.App)) {
      throw new Error("AppOfAppsChart must be the direct child of an cdk8s App");
    }

    const cdkApp = scope as cdk8s.App;

    for (let chart in cdkApp.charts) {
      console.log(chart.toString());
    }
  }
}
