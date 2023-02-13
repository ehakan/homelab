import * as cdk8s from "cdk8s";
import { Construct } from "constructs";

import * as argo from "../../imports/argoproj.io"
export class AppOfAppsChart extends cdk8s.Chart {
  constructor(scope: Construct, id: string, props: cdk8s.ChartProps = {
    namespace: "argocd",
  }) {
    super(scope, id, props);

    if (!(scope instanceof cdk8s.App)) {
      throw new Error("AppOfAppsChart must be defined right under an app");
    }

    const cdkApp = scope as cdk8s.App;

    for (let chart in cdkApp.charts) {
      console.log(cdk8s.Names.toLabelValue(chart));
    }

    debugger;
  }
}
