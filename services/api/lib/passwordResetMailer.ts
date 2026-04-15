import nodemailer from 'nodemailer';

const DEFAULT_TOKEN_TTL_MINUTES = 30;

type MailConfig = {
  resetUrlBase: string;
  tokenTtlMinutes: number;
  smtpHost: string;
  smtpPort: number;
  smtpSecure: boolean;
  smtpUser: string;
  smtpPass: string;
  smtpFrom: string;
};

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}

function parseBoolean(value: string | undefined): boolean {
  if (!value) {
    return false;
  }

  const normalized = value.trim().toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
}

function readMailConfig(): MailConfig {
  const resetUrlBase = (process.env.PASSWORD_RESET_URL || '').trim();
  const smtpHost = (process.env.SMTP_HOST || '').trim();
  const smtpUser = (process.env.SMTP_USER || '').trim();
  const smtpPass = process.env.SMTP_PASS || '';
  const smtpFrom = (process.env.SMTP_FROM || '').trim();
  const smtpPort = parsePositiveInteger(process.env.SMTP_PORT, 587);
  const smtpSecure = parseBoolean(process.env.SMTP_SECURE) || smtpPort === 465;
  const tokenTtlMinutes = parsePositiveInteger(
    process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES,
    DEFAULT_TOKEN_TTL_MINUTES,
  );

  const missing: string[] = [];
  if (!resetUrlBase) missing.push('PASSWORD_RESET_URL');
  if (!smtpHost) missing.push('SMTP_HOST');
  if (!smtpUser) missing.push('SMTP_USER');
  if (!smtpPass) missing.push('SMTP_PASS');
  if (!smtpFrom) missing.push('SMTP_FROM');

  if (missing.length > 0) {
    throw new Error(
      `Password reset email is not configured. Missing: ${missing.join(', ')}`,
    );
  }

  return {
    resetUrlBase,
    tokenTtlMinutes,
    smtpHost,
    smtpPort,
    smtpSecure,
    smtpUser,
    smtpPass,
    smtpFrom,
  };
}

export function getPasswordResetTokenTtlMinutes(): number {
  return readMailConfig().tokenTtlMinutes;
}

export function buildPasswordResetLink(rawToken: string): string {
  const { resetUrlBase } = readMailConfig();
  const resetUrl = new URL(resetUrlBase);
  resetUrl.searchParams.set('token', rawToken);
  return resetUrl.toString();
}

export async function sendPasswordResetEmail(params: {
  toEmail: string;
  resetLink: string;
  tokenTtlMinutes: number;
}): Promise<void> {
  const config = readMailConfig();

  const transporter = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpSecure,
    auth: {
      user: config.smtpUser,
      pass: config.smtpPass,
    },
  });

  await transporter.sendMail({
    from: config.smtpFrom,
    to: params.toEmail,
    subject: 'Hermit Home password reset',
    text: [
      'We received a request to reset your Hermit Home password.',
      '',
      `Reset link: ${params.resetLink}`,
      '',
      `This link will expire in ${params.tokenTtlMinutes} minutes.`,
      'If you did not request this change, you can ignore this email.',
    ].join('\n'),
    html: [
      '<p>We received a request to reset your Hermit Home password.</p>',
      `<p><a href="${params.resetLink}">Reset your password</a></p>`,
      `<p>This link will expire in <strong>${params.tokenTtlMinutes} minutes</strong>.</p>`,
      '<p>If you did not request this change, you can ignore this email.</p>',
    ].join(''),
  });
}
