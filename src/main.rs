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

const OPTIMIZE_DS_YESTERDAY: &str = "yesterday";

/*
 * Lambda function handler
 */
async fn func<'a>(event: LambdaEvent<CloudWatchEvent>) -> Result<Value, Error> {
    use deltalake::PartitionFilter;
    use chrono::*;

    debug!("CloudWatch event: {:?}", event);
    let location = std::env::var("DATALAKE_LOCATION")?;
    let table = deltalake::open_table(&location).await?;

    let mut filters = vec![];
    // This variable only exists to provide a long enough lifetime for
    // any PartitionFilter values created
    let mut _ds = String::new();

    if let Ok(ds_filter) = std::env::var("OPTIMIZE_DS") {
        match ds_filter.as_str() {
            OPTIMIZE_DS_YESTERDAY => {
                if let Some(yesterday) = Utc::now().checked_sub_days(Days::new(1)) {
                    _ds = format!("{}", yesterday.format("%Y-%m-%d"));
                    let partition = ("ds", "=", _ds.as_str());
                    info!("Optimizing with partition: {:?}", partition);
                    filters.push(PartitionFilter::try_from(partition)?);
                }
            },
            unknown => warn!("Unknown value of OPTIMIZE_DS: {}", unknown),
        }
    }

    let (table, metrics) = OptimizeBuilder::new(table.object_store(), table.state)
        .with_filters(filters.as_slice())
        .await?;

    debug!("table: optimize: {:?}", table);
    info!("table: metrics: {:?}", metrics);

    Ok(json!({
        "message": format!("Optimized table at: {}", location)
    }))
}
