// Nightly Lambda. Writes status.json + insights.json to both site buckets.
//
//   status.json  — Synthetics canary health + 30-day roll-up
//   insights.json — Athena over CloudFront access logs

import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { CloudWatchClient, GetMetricStatisticsCommand } from "@aws-sdk/client-cloudwatch";
import {
  SyntheticsClient,
  DescribeCanariesLastRunCommand,
  GetCanaryRunsCommand,
} from "@aws-sdk/client-synthetics";
import {
  AthenaClient,
  StartQueryExecutionCommand,
  GetQueryExecutionCommand,
  GetQueryResultsCommand,
} from "@aws-sdk/client-athena";

const s3   = new S3Client({ region: "us-west-2" });   // primary
const s3dr = new S3Client({ region: "us-east-1" });   // DR
const cw   = new CloudWatchClient({});
const syn  = new SyntheticsClient({});
const athena = new AthenaClient({});

const {
  SITE_BUCKET,
  SITE_BUCKET_DR,
  CANARY_NAME,
  ATHENA_DB,
  ATHENA_WORKGROUP,
} = process.env;

// URLs the canary probes. Keep in sync with lambdas/canary/nodejs/node_modules/index.js
const CANARY_TARGETS = ["/", "/work/", "/architecture/"];

const isoDate = (offsetDays = 0) => {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
};

async function putJson(key, body) {
  const payload = JSON.stringify({ generatedAt: new Date().toISOString(), ...body }, null, 2);
  const params = {
    Key: key,
    Body: payload,
    ContentType: "application/json",
    CacheControl: "public, max-age=300, must-revalidate",
  };
  await Promise.all([
    s3.send(new PutObjectCommand({ Bucket: SITE_BUCKET,    ...params })),
    s3dr.send(new PutObjectCommand({ Bucket: SITE_BUCKET_DR, ...params })),
  ]);
}

// ---------- STATUS ----------

async function collectStatus() {
  // Last run + basic metadata.
  const lastRunRes = await syn.send(new DescribeCanariesLastRunCommand({ Names: [CANARY_NAME] }));
  const lastRun = lastRunRes.CanariesLastRun?.[0]?.LastRun;
  const startedAt = lastRun?.Timeline?.Started;
  const completedAt = lastRun?.Timeline?.Completed;

  // 30-day success rate from CloudWatch metrics.
  const now = new Date();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const successMetric = await cw.send(new GetMetricStatisticsCommand({
    Namespace: "CloudWatchSynthetics",
    MetricName: "SuccessPercent",
    Dimensions: [{ Name: "CanaryName", Value: CANARY_NAME }],
    StartTime: thirtyDaysAgo,
    EndTime: now,
    Period: 3600,
    Statistics: ["Average", "SampleCount"],
  }));
  const dp = successMetric.Datapoints ?? [];
  const totalRuns30d = dp.reduce((s, d) => s + (d.SampleCount ?? 0), 0);
  const weightedSum = dp.reduce((s, d) => s + (d.Average ?? 0) * (d.SampleCount ?? 0), 0);
  const successRate30d = totalRuns30d > 0 ? weightedSum / totalRuns30d : null;
  const failedRuns30d = totalRuns30d > 0
    ? Math.round(totalRuns30d - (weightedSum / 100))
    : 0;

  // Last 8 runs — powers the "recent runs" table.
  const runsRes = await syn.send(new GetCanaryRunsCommand({ Name: CANARY_NAME, MaxResults: 8 }));
  const recentRuns = (runsRes.CanaryRuns ?? []).map((r) => ({
    runAt: r.Timeline?.Completed?.toISOString() ?? r.Timeline?.Started?.toISOString(),
    status: r.Status?.State ?? "unknown",
    durationMs: r.Timeline?.Started && r.Timeline?.Completed
      ? r.Timeline.Completed.getTime() - r.Timeline.Started.getTime()
      : null,
  }));

  // Per-URL breakdown — canary script tests these together so we mirror the last-run status.
  const endpoints = CANARY_TARGETS.map((url) => ({
    url,
    status: lastRun?.Status?.State ?? "unknown",
    durationMs: startedAt && completedAt
      ? Math.round((completedAt.getTime() - startedAt.getTime()) / CANARY_TARGETS.length)
      : null,
  }));

  return {
    canary: CANARY_NAME,
    lastRunStatus: lastRun?.Status?.State ?? "unknown",
    lastRunAt: completedAt?.toISOString() ?? null,
    lastRunDurationMs: startedAt && completedAt
      ? completedAt.getTime() - startedAt.getTime()
      : null,
    successRate30d,
    totalRuns30d,
    failedRuns30d,
    endpoints,
    recentRuns,
    statusUrl: `https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#synthetics:canary/detail/${CANARY_NAME}`,
  };
}

// ---------- INSIGHTS ----------

async function runAthena(sql) {
  const start = await athena.send(new StartQueryExecutionCommand({
    QueryString: sql,
    QueryExecutionContext: { Database: ATHENA_DB },
    WorkGroup: ATHENA_WORKGROUP,
  }));
  const id = start.QueryExecutionId;
  for (let i = 0; i < 40; i++) {
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
    const [topPagesRaw, refsRaw, statsRaw] = await Promise.all([
      runAthena(`
        SELECT uri, COUNT(*) AS hits
        FROM \`${ATHENA_DB}\`.cloudfront_logs
        WHERE log_date >= current_date - interval '7' day
          AND status = 200
          AND uri NOT LIKE '/_astro/%'
          AND uri NOT LIKE '/_assets/%'
          AND uri NOT LIKE '/fonts/%'
          AND uri NOT LIKE '/assets/%'
          AND uri NOT LIKE '/new-assets/%'
          AND uri NOT LIKE '/showcase/%'
          AND uri NOT LIKE '%.json'
          AND uri NOT LIKE '%.xml'
          AND uri NOT LIKE '%.png'
          AND uri NOT LIKE '%.webp'
          AND uri NOT LIKE '%.jpg'
          AND uri NOT LIKE '%.svg'
          AND uri NOT LIKE '%.ico'
        GROUP BY uri
        ORDER BY hits DESC
        LIMIT 15
      `),
      runAthena(`
        SELECT
          CASE
            WHEN referrer = '-' OR referrer = '' THEN '(direct)'
            WHEN regexp_like(referrer, 'https?://([^/]+)') THEN regexp_extract(referrer, 'https?://([^/]+)', 1)
            ELSE referrer
          END AS domain,
          COUNT(*) AS hits
        FROM \`${ATHENA_DB}\`.cloudfront_logs
        WHERE log_date >= current_date - interval '7' day
          AND referrer NOT LIKE '%showcase.dram-soc.org%'
        GROUP BY 1
        ORDER BY hits DESC
        LIMIT 8
      `),
      runAthena(`
        SELECT
          COUNT(*) AS total_requests,
          COUNT(DISTINCT request_ip) AS unique_viewers,
          SUM(CAST(bytes AS bigint)) AS bytes_served,
          SUM(CASE WHEN result_type IN ('Hit', 'RefreshHit') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS cache_hit_ratio
        FROM \`${ATHENA_DB}\`.cloudfront_logs
        WHERE log_date >= current_date - interval '7' day
      `),
    ]);

    const stats = statsRaw[0] ?? {};
    return {
      periodStart: isoDate(-7),
      periodEnd: isoDate(),
      totalRequests: parseInt(stats.total_requests ?? "0", 10),
      uniqueViewers: parseInt(stats.unique_viewers ?? "0", 10),
      cacheHitRatio: parseFloat(stats.cache_hit_ratio ?? "0"),
      bytesServedMB: parseFloat(stats.bytes_served ?? "0") / (1024 * 1024),
      topPages: topPagesRaw.map((r) => ({ uri: r.uri, hits: parseInt(r.hits, 10) })),
      topReferrers: refsRaw.map((r) => ({ domain: r.domain, hits: parseInt(r.hits, 10) })),
    };
  } catch (err) {
    return {
      periodStart: isoDate(-7),
      periodEnd: isoDate(),
      topPages: [],
      topReferrers: [],
      warning: err.message,
    };
  }
}

// ---------- HANDLER ----------

export async function handler() {
  const [status, insights] = await Promise.allSettled([
    collectStatus(),
    collectInsights(),
  ]);

  const write = async (key, result) => {
    if (result.status === "fulfilled") return putJson(key, result.value);
    return putJson(key, { error: result.reason?.message ?? String(result.reason) });
  };

  await Promise.all([
    write("status.json", status),
    write("insights.json", insights),
  ]);

  return { ok: true, wrote: ["status.json", "insights.json"] };
}
