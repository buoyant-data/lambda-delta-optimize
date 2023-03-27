/*
 * This _very_ simple AWS Lambda function relies on the optimize functionality built into the
 * deltalake module to optimize the table specified by `DATALAKE_LOCATION` in the environment
 * variables
 */

use aws_lambda_events::cloudwatch_events::CloudWatchEvent;
use deltalake::operations::optimize::OptimizeBuilder;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use log::*;
use serde_json::json;
use serde_json::Value;

#[tokio::main]
async fn main() -> Result<(), Error> {
    pretty_env_logger::init();

    info!("Starting the Lambda runtime");
    let func = service_fn(func);
    lambda_runtime::run(func).await
}

/*
 * Lambda function handler
 */
async fn func(event: LambdaEvent<CloudWatchEvent>) -> Result<Value, Error> {
    debug!("CloudWatch event: {:?}", event);
    let location = std::env::var("DATALAKE_LOCATION")?;
    let table = deltalake::open_table(&location).await?;
    let (table, metrics) = OptimizeBuilder::new(table.object_store(), table.state).await?;

    debug!("table: optimize: {:?}", table);
    info!("table: metrics: {:?}", metrics);

    Ok(json!({
        "message": format!("Optimized table at: {}", location)
    }))
}
