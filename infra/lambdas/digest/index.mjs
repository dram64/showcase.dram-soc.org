// Nightly Lambda — queries Cost Explorer + Synthetics + Athena and writes
// three JSON files to the site bucket that the /status, /cost, and
// /insights static pages fetch client-side. Refreshed via EventBridge cron.

import { CostExplorerClient, GetCostAndUsageCommand } from "@aws-sdk/client-cost-explorer";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { SyntheticsClient, DescribeCanariesLastRunCommand } from "@aws-sdk/client-synthetics";
import { AthenaClient, StartQueryExecutionCommand, GetQueryExecutionCommand, GetQueryResultsCommand } from "@aws-sdk/client-athena";

const ce = new CostExplorerClient({ region: "us-east-1" });
const s3 = new S3Client({ region: "us-west-2" });   // primary bucket
const s3dr = new S3Client({ region: "us-east-1" }); // DR bucket
const syn = new SyntheticsClient({});
const athena = new AthenaClient({});

const {
  SITE_BUCKET,
  SITE_BUCKET_DR,
  CANARY_NAME,
  ATHENA_DB,
  ATHENA_WORKGROUP,
} = process.env;

function toIsoDate(offsetDays = 0) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}

async function putJson(key, body) {
  const payload = JSON.stringify({ generatedAt: new Date().toISOString(), ...body }, null, 2);
  await Promise.all([
    s3.send(new PutObjectCommand({
      Bucket: SITE_BUCKET,
      Key: key,
      Body: payload,
      ContentType: "application/json",
      CacheControl: "public, max-age=300, must-revalidate",
    })),
    s3dr.send(new PutObjectCommand({
      Bucket: SITE_BUCKET_DR,
      Key: key,
      Body: payload,
      ContentType: "application/json",
      CacheControl: "public, max-age=300, must-revalidate",
    })),
  ]);
}

async function collectCost() {
  const res = await ce.send(new GetCostAndUsageCommand({
    TimePeriod: { Start: toIsoDate(-30), End: toIsoDate() },
    Granularity: "MONTHLY",
    Metrics: ["UnblendedCost"],
    GroupBy: [{ Type: "DIMENSION", Key: "SERVICE" }],
  }));
  const services = (res.ResultsByTime?.[0]?.Groups ?? [])
    .map((g) => ({
      service: g.Keys?.[0] ?? "unknown",
      cost:    parseFloat(g.Metrics?.UnblendedCost?.Amount ?? "0"),
    }))
    .filter((s) => s.cost > 0.0001)
    .sort((a, b) => b.cost - a.cost);

  const total = services.reduce((sum, s) => sum + s.cost, 0);
  return { periodStart: toIsoDate(-30), periodEnd: toIsoDate(), total, services };
}

async function collectStatus() {
  const res = await syn.send(new DescribeCanariesLastRunCommand({ Names: [CANARY_NAME] }));
  const lastRun = res.CanariesLastRun?.[0]?.LastRun;
  return {
    canary: CANARY_NAME,
    lastRunStatus: lastRun?.Status?.State ?? "unknown",
    lastRunAt: lastRun?.Timeline?.Completed?.toISOString() ?? null,
    lastRunDurationMs: lastRun?.Timeline?.Started && lastRun?.Timeline?.Completed
      ? (lastRun.Timeline.Completed.getTime() - lastRun.Timeline.Started.getTime())
      : null,
    statusUrl: `https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#synthetics:canary/detail/${CANARY_NAME}`,
  };
}

async function runAthena(sql) {
  const start = await athena.send(new StartQueryExecutionCommand({
    QueryString: sql,
    QueryExecutionContext: { Database: ATHENA_DB },
    WorkGroup: ATHENA_WORKGROUP,
  }));
  const id = start.QueryExecutionId;
  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    const st = await athena.send(new GetQueryExecutionCommand({ QueryExecutionId: id }));
    const state = st.QueryExecution?.Status?.State;
    if (state === "SUCCEEDED") break;
    if (state === "FAILED" || state === "CANCELLED") {
      throw new Error(`Athena query ${state}: ${st.QueryExecution?.Status?.StateChangeReason}`);
    }
  }
  const results = await athena.send(new GetQueryResultsCommand({ QueryExecutionId: id }));
  const rows = results.ResultSet?.Rows ?? [];
  const header = rows[0]?.Data?.map((c) => c.VarCharValue) ?? [];
  return rows.slice(1).map((r) => {
    const obj = {};
    r.Data?.forEach((c, i) => { obj[header[i] ?? `col${i}`] = c.VarCharValue; });
    return obj;
  });
}

async function collectInsights() {
  try {
    const topPages = await runAthena(`
      SELECT uri, COUNT(*) AS hits
      FROM ${ATHENA_DB}.cloudfront_logs
      WHERE log_date >= current_date - interval '7' day
        AND status = 200
        AND uri NOT LIKE '/_assets/%'
        AND uri NOT LIKE '/fonts/%'
        AND uri NOT LIKE '/assets/%'
      GROUP BY uri
      ORDER BY hits DESC
      LIMIT 10
    `);
    return { period: "last 7 days", topPages };
  } catch (err) {
    return { period: "last 7 days", topPages: [], warning: err.message };
  }
}

export async function handler() {
  const [cost, status, insights] = await Promise.allSettled([
    collectCost(),
    collectStatus(),
    collectInsights(),
  ]);

  const write = async (key, result) => {
    if (result.status === "fulfilled") return putJson(key, result.value);
    return putJson(key, { error: result.reason?.message ?? String(result.reason) });
  };

  await Promise.all([
    write("cost.json", cost),
    write("status.json", status),
    write("insights.json", insights),
  ]);

  return { ok: true, wrote: ["cost.json", "status.json", "insights.json"] };
}
