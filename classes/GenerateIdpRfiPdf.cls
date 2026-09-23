/**
 * Renders the Markdown intake summary held in Opportunity.IDP_RFI__c to a PDF
 * and files it against the Opportunity.
 *
 * Flow passes the whole record and the summary is read straight off it. The
 * field is never re-queried, so an uncommitted value still renders.
 *
 * The Visualforce page runs in its own request and cannot see the in-memory
 * record, so the text is handed over as a URL parameter. That caps how long
 * the summary can be - see MAX_ENCODED_LENGTH.
 *
 * One class, three roles:
 *   1. Controller for the IDP_RFI_Summary Visualforce page.
 *   2. Flow-invocable entry point.
 *   3. Queueable that renders and attaches the PDF.
 *
 * The Queueable is required. getContentAsPDF() is treated as a callout, so
 * running it in the same transaction as the Flow's own DML raises
 * "You have uncommitted work pending".
 */
public with sharing class GenerateIdpRfiPdf {

    public class PdfException extends Exception {}

    private static final Integer BATCH_SIZE   = 5;
    private static final String  TITLE_PREFIX = 'IDP RFI Summary - ';

    /** URL-encoded content longer than this will not survive the request. */
    private static final Integer MAX_ENCODED_LENGTH = 6000;

    /** Placeholder values the extractor emits for "nothing here". */
    private static final Set<String> NOISE = new Set<String>{
        'not specified', 'none specified', 'not applicable', 'n/a', 'none', '-'
    };
    /** Set false to print every line, including the placeholders above. */
    private static final Boolean HIDE_NOISE = true;

    // "  - **Label:** value"  ->  group(1) indent, group(2) content
    private static final Pattern BULLET =
        Pattern.compile('^([ \\t]*)[-*+]\\s+(.*)$');
    // "**Label:** value" or "**Label**: value"
    private static final Pattern LABELLED =
        Pattern.compile('^\\*\\*(.+?):?\\*\\*:?\\s*(.*)$');

    // ============================================== Visualforce controller

    public String recordName { get; private set; }
    public String bodyHtml   { get; private set; }

    public GenerateIdpRfiPdf() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        recordName = params.get('name');
        bodyHtml   = buildHtml(params.get('data'));
    }

    // ========================================================== invocable

    @InvocableMethod(
        label='Generate IDP RFI PDF'
        description='Renders the Opportunity IDP RFI summary to a PDF and attaches it as a file.'
        category='IDP')
    public static void generate(List<Opportunity> records) {

        List<Opportunity> valid = new List<Opportunity>();

        for (Opportunity o : records) {
            // Read the value off the record as supplied - never re-query it.
            if (o != null && o.Id != null && String.isNotBlank(o.IDP_RFI__c)) {
                valid.add(o);
            }
        }
        if (valid.isEmpty()) {
            return;
        }

        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(LoggingLevel.WARN, 'Queueable limit reached, skipping ' + valid.size() + ' record(s)');
            return;
        }

        System.enqueueJob(new PdfJob(valid));
    }

    // ========================================================== queueable

    public class PdfJob implements Queueable, Database.AllowsCallouts {

        private List<Opportunity> records;

        public PdfJob(List<Opportunity> records) {
            this.records = records;
        }

        public void execute(QueueableContext ctx) {

            List<Opportunity> current   = new List<Opportunity>();
            List<Opportunity> remaining = new List<Opportunity>();

            for (Opportunity o : records) {
                if (current.size() < BATCH_SIZE) {
                    current.add(o);
                } else {
                    remaining.add(o);
                }
            }

            try {
                run(current);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'GenerateIdpRfiPdf failed: '
                    + e.getMessage() + '\n' + e.getStackTraceString());
            }

            if (!remaining.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new PdfJob(remaining));
            }
        }
    }

    // ============================================================= worker

    @TestVisible
    private static void run(List<Opportunity> records) {

        Set<Id> ids = new Set<Id>();
        for (Opportunity o : records) {
            ids.add(o.Id);
        }

        Map<String, Id> existing = new Map<String, Id>();
        for (ContentDocumentLink cdl : [
                SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :ids]) {
            existing.put(cdl.LinkedEntityId + '|' + cdl.ContentDocument.Title,
                         cdl.ContentDocumentId);
        }

        // Render everything before any DML - getContentAsPDF is a callout.
        List<ContentVersion> versions = new List<ContentVersion>();

        for (Opportunity o : records) {

            String name  = String.isBlank(o.Name) ? String.valueOf(o.Id) : o.Name;
            String title = (TITLE_PREFIX + name).abbreviate(200);

            ContentVersion cv = new ContentVersion(
                Title          = title,
                PathOnClient   = title + '.pdf',
                VersionData    = renderPdf(o.IDP_RFI__c, name),
                IsMajorVersion = true
            );

            Id priorDocId = existing.get(o.Id + '|' + title);
            if (priorDocId != null) {
                cv.ContentDocumentId = priorDocId;
            } else {
                cv.FirstPublishLocationId = o.Id;
            }

            versions.add(cv);
        }

        List<Database.SaveResult> results = Database.insert(versions, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'ContentVersion insert failed for "'
                    + versions[i].Title + '": ' + results[i].getErrors());
            }
        }
    }

    private static Blob renderPdf(String markdown, String recordName) {

        String encoded = EncodingUtil.urlEncode(markdown, 'UTF-8');
        if (encoded.length() > MAX_ENCODED_LENGTH) {
            throw new PdfException('Summary too long to pass by URL ('
                + encoded.length() + ' encoded chars, limit ' + MAX_ENCODED_LENGTH
                + '). The page cannot read uncommitted data, so the only way to '
                + 'render content this large is to commit the field first and '
                + 'have the page query it.');
        }

        PageReference pr = Page.IDP_RFI_Summary;
        pr.getParameters().put('data', markdown);
        pr.getParameters().put('name', recordName);

        if (Test.isRunningTest()) {
            return Blob.valueOf('TEST-PDF-CONTENT');
        }
        return pr.getContentAsPDF();
    }

    // ======================================================= html builder

    /**
     * Converts the Markdown summary into a bordered two-column table.
     *
     *   "## 1. SECTION"        -> full-width section bar
     *   "- **Label:** value"   -> label / value row
     *   "- **Label:**"         -> group header row (no value)
     *   leading whitespace     -> one nesting level per two spaces
     *
     * Child bullets are indented only when the source indents them. Where the
     * extractor emits every bullet flush left the rows stay flat, rather than
     * inventing a hierarchy that is not in the text.
     */
    public static String buildHtml(String markdown) {

        if (String.isBlank(markdown)) {
            return '<p class="empty">No intake summary data available.</p>';
        }

        List<String> h = new List<String>();
        h.add('<table class="kv">');

        for (String rawLine : markdown.split('\n')) {

            String line = rawLine.replace('\r', '');
            if (String.isBlank(line)) {
                continue;
            }

            String trimmed = line.trim();

            // "## 1. BID INTAKE & CONTRACTUAL / PURSUIT CONDITIONS"
            if (trimmed.startsWith('#')) {
                String title = stripBold(trimmed.replaceFirst('^#+\\s*', '')).trim();
                if (String.isNotBlank(title)) {
                    h.add('<tr class="sec"><td colspan="2">' + esc(title) + '</td></tr>');
                }
                continue;
            }

            Matcher bullet = BULLET.matcher(line);

            if (!bullet.matches()) {
                // Loose prose between bullets.
                h.add('<tr><td colspan="2">' + esc(stripBold(trimmed)) + '</td></tr>');
                continue;
            }

            Integer spaces = bullet.group(1).replace('\t', '  ').length();
            Integer depth  = (spaces == 0) ? 0 : Math.max(1, spaces / 2);
            String  body   = bullet.group(2).trim();

            Matcher labelled = LABELLED.matcher(body);

            if (!labelled.matches()) {
                // Bullet with no bold label.
                h.add('<tr><td class="lbl">' + indent(depth) + '&#8226;</td>'
                    + '<td>' + esc(stripBold(body)) + '</td></tr>');
                continue;
            }

            String label = stripBold(labelled.group(1)).trim();
            String value = stripBold(labelled.group(2)).trim();

            // "- **Key dates:**" with nothing after it heads the rows below.
            if (String.isBlank(value)) {
                h.add('<tr class="sub"><td colspan="2">'
                    + indent(depth) + esc(label) + '</td></tr>');
                continue;
            }

            if (HIDE_NOISE && NOISE.contains(value.toLowerCase())) {
                continue;
            }

            h.add('<tr><td class="lbl">' + indent(depth) + esc(label) + '</td>'
                + '<td>' + esc(value) + '</td></tr>');
        }

        h.add('</table>');
        return String.join(h, '');
    }

    // ============================================================ helpers

    private static String indent(Integer depth) {
        String s = '';
        for (Integer i = 0; i < depth; i++) {
            s += '&#160;&#160;&#160;&#160;';
        }
        return s;
    }

    private static String stripBold(String s) {
        return s == null ? '' : s.replace('**', '').replace('__', '');
    }

    private static String esc(String s) {
        return s == null ? '' : s.escapeHtml4();
    }
}