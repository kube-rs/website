use std::{sync::Arc, time::Duration};
use futures::StreamExt;
use k8s_openapi::api::{autoscaling::v2::HorizontalPodAutoscaler, apps::v1::Deployment};
use kube::{
    Api, Client, ResourceExt,
    runtime::reflector::ObjectRef,
    runtime::controller::{Action, Controller},
};

#[derive(thiserror::Error, Debug)]
pub enum Error {}
pub type Result<T, E = Error> = std::result::Result<T, E>;

#[tokio::main]
async fn main() -> Result<(), kube::Error> {
    let client = Client::try_default().await?;
    let deploys = Api::<Deployment>::all(client.clone());
    let hpas = Api::<HorizontalPodAutoscaler>::all(client);

    // map hpa changes to deployment events through scaleTargetRef
    let mapper = |obj: HorizontalPodAutoscaler| {
        obj.spec.map(|hspec| {
            let crossref = hspec.scale_target_ref;
            if crossref.kind == "Deployment" {
                Some(ObjectRef::new_with(&crossref.name, ()))
            } else {
                None
            }
        }).flatten()
    };

    Controller::new(deploys.clone(), Default::default())
        .watches(hpas, Default::default(), mapper)
        .run(reconcile, error_policy, Arc::new(()))
        .for_each(|_| futures::future::ready(()))
        .await;

    Ok(())
}

async fn reconcile(obj: Arc<Deployment>, _ctx: Arc<()>) -> Result<Action> {
    println!("reconcile request: {}", obj.name_any());
    Ok(Action::requeue(Duration::from_secs(3600)))
}

fn error_policy(_obj: Arc<Deployment>, _error: &Error, _ctx: Arc<()>) -> Action {
    Action::requeue(Duration::from_secs(5))
}
