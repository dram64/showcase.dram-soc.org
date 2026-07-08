import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "node:crypto";

const ses = new SESClient({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const {
  RECIPIENT_EMAIL,
  SENDER_EMAIL,
  TABLE_NAME,
} = process.env;

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  };
}

function sanitize(str) {
  return String(str || "").slice(0, 4000).replace(/[\r\n]{3,}/g, "\n\n");
}

function isValidEmail(str) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(String(str || ""));
}

export async function handler(event) {
  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return json(400, { error: "Invalid JSON" });
  }

  const name    = sanitize(payload.name).slice(0, 120);
  const email   = sanitize(payload.email).slice(0, 200);
  const subject = sanitize(payload.subject).slice(0, 200);
  const body    = sanitize(payload.body);
  const hp      = String(payload.website || "");

  if (hp.length > 0)         return json(200, { ok: true });
  if (!name || !email || !body) return json(400, { error: "Missing required fields." });
  if (!isValidEmail(email))     return json(400, { error: "Invalid email address." });

  const id = randomUUID();
  const receivedAt = new Date().toISOString();

  try {
    await ddb.send(new PutCommand({
      TableName: TABLE_NAME,
      Item: { id, name, email, subject, body, receivedAt },
    }));
  } catch (err) {
    console.error("DDB write failed", err);
  }

  try {
    await ses.send(new SendEmailCommand({
      Source: SENDER_EMAIL,
      Destination: { ToAddresses: [RECIPIENT_EMAIL] },
      ReplyToAddresses: [email],
      Message: {
        Subject: { Data: `[dram-soc.org] ${subject || "Contact form"}`, Charset: "UTF-8" },
        Body: {
          Text: {
            Charset: "UTF-8",
            Data: [
              `New message from ${name} <${email}>`,
              `Received: ${receivedAt}`,
              `ID: ${id}`,
              ``,
              body,
            ].join("\n"),
          },
        },
      },
    }));
  } catch (err) {
    console.error("SES send failed", err);
    return json(502, { error: "Could not send message. Try again shortly." });
  }

  return json(200, { ok: true });
}
