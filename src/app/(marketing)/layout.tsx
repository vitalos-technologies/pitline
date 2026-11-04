import { AskbridgeWidget } from "@/components/askbridge/askbridge-widget";
import { pitlineAskbridgeWidget } from "@/lib/askbridge/config";

/**
 * Pitline's own marketing pages (`/`, `/contact`): the admin host's public face. Only here does Pitline's
 * Askbridge chat load (DECISIONS D28), lazily once the page is idle; the garage admin, sign-in, sign-up,
 * the super admin and garage booking sites (rewritten to /_site by the proxy) never render this layout.
 */
export default function MarketingLayout({ children }: { children: React.ReactNode }) {
  const widget = pitlineAskbridgeWidget();
  return (
    <>
      {children}
      {widget ? <AskbridgeWidget src={widget.scriptUrl} siteKey={widget.siteKey} /> : null}
    </>
  );
}
