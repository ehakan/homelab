import { Construct } from "constructs";

import * as kplus from "cdk8s-plus-25";
import { Chart } from "cdk8s";

export interface PublicRepositoryProps {
  readonly repositoryDefinition: RepositoryDefinition;

  /**
  * Repository name
  *
  * @default Construct ID
  */
  readonly name?: string;

  readonly namespace?: string;
}

type GitRepositoryDefinition = {
  type: "git";

  /**
  * Git Repository URL
  */
  url: string;

  /**
  * Do not enforce TLS
  * @default false
  */
  insecure?: `${boolean}`;

  /**
  * Enable git-lfs support.
  * @default false
  */
  enableLfs?: `${boolean}`;
}

type HelmRepositoryDefinition = {
  type: "helm";

  /**
  * A Helm Repository Url
  */
  url: string;

  /**
  * Helm Chart in the Helm Repository
  */
  name?: string;
}

type RepositoryDefinition = GitRepositoryDefinition | HelmRepositoryDefinition;

/**
* An ArgoCD Declarative Repository Definition
* Since Repositories can contain credentials in them, they are represented as Secrets.
* In the case of PublicRepsitories, we can just embed them in code.
*/
export class PublicRepository extends Construct {
  constructor(scope: Construct, id: string, props: PublicRepositoryProps) {
    super(scope, id);

    const name = props.name ?? id;
    const namespace = props.namespace ?? Chart.of(this).namespace ?? "argocd";

    const secret = new kplus.Secret(this, 'repository', {
      metadata: {
        name,
        namespace,
        labels: {
          "argocd.argoproj.io/secret-type": "repository",
        }
      },
      stringData: props.repositoryDefinition,
    });
  }
}
