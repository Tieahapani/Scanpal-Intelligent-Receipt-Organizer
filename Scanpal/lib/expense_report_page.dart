import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/monthly_summary_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExpenseReportPage extends StatefulWidget {
  const ExpenseReportPage({
    super.key,
    required this.dateRange,
    required this.stats,
    required this.categoryBreakdown,
    required this.vendorBreakdown,
    required this.currency,
  });

  final DateTimeRange dateRange;
  final QuickStats stats;
  final List<CategoryBreakdown> categoryBreakdown;
  final List<VendorBreakdown> vendorBreakdown;
  final NumberFormat currency;

  @override
  State<ExpenseReportPage> createState() => _ExpenseReportPageState();
}

class _ExpenseReportPageState extends State<ExpenseReportPage> {
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _generateAndShowReport();
  }

  Future<void> _generateAndShowReport() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      final aiSummary = await _callGeminiAPI();
      final pdfBytes = await _generatePDF(aiSummary);

      setState(() {
        _isGenerating = false;
      });

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => Uint8List.fromList(pdfBytes),
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating report: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _callGeminiAPI() async {
    // TODO: Replace with your Gemini API key
    const apiKey = 'AIzaSyCAnr5KqnEg-YIMTq5_OAubnoLRGxAB9mg';
    const apiUrl =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

    final dateFormatter = DateFormat('MMM d, y');
    final startDate = dateFormatter.format(widget.dateRange.start);
    final endDate = dateFormatter.format(widget.dateRange.end);
    final totalExpense = widget.currency.format(widget.stats.currentTotal);
    final dailyAverage =
        widget.currency.format(widget.stats.dailyAverage ?? 0);

    // Build category breakdown text — ALL categories
    final categoryText = widget.categoryBreakdown
        .map((cat) =>
            '${cat.categoryName}: ${widget.currency.format(cat.total)} (${cat.percentage.toStringAsFixed(1)}%)')
        .join('\n');

    // Build vendor breakdown text — ALL vendors
    final vendorText = widget.vendorBreakdown
        .map((vendor) =>
            '${vendor.vendorName}: ${widget.currency.format(vendor.total)} (${vendor.percentage.toStringAsFixed(1)}%)')
        .join('\n');

    final prompt = '''
Analyze this expense data and provide a concise financial summary in a professional yet approachable tone.

EXPENSE DATA:
Period: $startDate to $endDate
Total Spending: $totalExpense
Daily Average: $dailyAverage
Transactions: ${widget.stats.receiptsCount}

All Categories (${widget.categoryBreakdown.length} total):
$categoryText

All Vendors (${widget.vendorBreakdown.length} total):
$vendorText

Provide a 4-paragraph analysis:

Paragraph 1: Spending Overview
Summarize the overall spending pattern for this period. Note if the daily average suggests controlled or high spending relative to the transaction count.

Paragraph 2: Category Analysis
Identify which category dominates spending and whether this allocation seems balanced. Point out any category that warrants attention.

Paragraph 3: Vendor Concentration
Analyze vendor spending distribution. Note if spending is concentrated with few vendors or well-distributed. Focus on the top 3-5 vendors but acknowledge the full distribution.

Paragraph 4: Actionable Recommendation
Provide one specific, actionable recommendation to optimize spending based on the data. Be direct and practical.

Guidelines:
- Write in second person ("You spent", "Your spending")
- Use exact figures from the data
- Be constructive, not judgmental
- No emojis, bullet points, or headers
- Each paragraph should be 2-3 sentences
- Focus on insights, not just restating numbers
''';

    final response = await http.post(
      Uri.parse('$apiUrl?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.4,
          'maxOutputTokens': 500,
        }
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final text =
          data['candidates'][0]['content']['parts'][0]['text'] as String;
      return text.trim();
    } else {
      throw Exception(
          'API returned ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<int>> _generatePDF(String aiSummary) async {
    final pdf = pw.Document();
    final dateFormatter = DateFormat('MMM d, y');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 30),
        build: (pw.Context context) {
          return [
            // ── Header ──
            pw.Container(
              padding:
                  const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom:
                      pw.BorderSide(width: 2, color: PdfColors.blue700),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'EXPENSE REPORT',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.Text(
                    '${dateFormatter.format(widget.dateRange.start)} – ${dateFormatter.format(widget.dateRange.end)}',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // ── Summary Row: Total | Daily Avg | Transactions ──
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  vertical: 14, horizontal: 16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TOTAL EXPENSES',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        widget.currency
                            .format(widget.stats.currentTotal),
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'DAILY AVG',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        widget.currency
                            .format(widget.stats.dailyAverage ?? 0),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'TRANSACTIONS',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        '${widget.stats.receiptsCount}',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 18),

            // ── Two-Column: Categories + Vendors side by side ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Category Breakdown (left)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CATEGORY BREAKDOWN',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey300),
                          borderRadius:
                              pw.BorderRadius.circular(4),
                        ),
                        child: pw.Table(
                          border: pw.TableBorder(
                            horizontalInside: pw.BorderSide(
                                color: PdfColors.grey200),
                          ),
                          columnWidths: {
                            0: const pw.FlexColumnWidth(3),
                            1: const pw.FlexColumnWidth(2),
                          },
                          children: [
                            pw.TableRow(
                              decoration:
                                  const pw.BoxDecoration(
                                      color:
                                          PdfColors.grey100),
                              children: [
                                pw.Padding(
                                  padding:
                                      const pw.EdgeInsets
                                          .all(6),
                                  child: pw.Text(
                                    'Category',
                                    style: pw.TextStyle(
                                      fontWeight: pw
                                          .FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding:
                                      const pw.EdgeInsets
                                          .all(6),
                                  child: pw.Text(
                                    'Amount',
                                    style: pw.TextStyle(
                                      fontWeight: pw
                                          .FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                    textAlign:
                                        pw.TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            ...widget.categoryBreakdown
                                .map((cat) {
                              return pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding:
                                        const pw.EdgeInsets
                                            .all(6),
                                    child: pw.Text(
                                      cat.categoryName,
                                      style:
                                          const pw.TextStyle(
                                              fontSize: 9),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding:
                                        const pw.EdgeInsets
                                            .all(6),
                                    child: pw.Text(
                                      widget.currency
                                          .format(cat.total),
                                      textAlign: pw
                                          .TextAlign.right,
                                      style: pw.TextStyle(
                                        fontWeight: pw
                                            .FontWeight.bold,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(width: 16),

                // Vendor Breakdown (right)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VENDOR BREAKDOWN',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColors.grey300),
                          borderRadius:
                              pw.BorderRadius.circular(4),
                        ),
                        child: pw.Table(
                          border: pw.TableBorder(
                            horizontalInside: pw.BorderSide(
                                color: PdfColors.grey200),
                          ),
                          columnWidths: {
                            0: const pw.FlexColumnWidth(3),
                            1: const pw.FlexColumnWidth(2),
                          },
                          children: [
                            pw.TableRow(
                              decoration:
                                  const pw.BoxDecoration(
                                      color:
                                          PdfColors.grey100),
                              children: [
                                pw.Padding(
                                  padding:
                                      const pw.EdgeInsets
                                          .all(6),
                                  child: pw.Text(
                                    'Vendor',
                                    style: pw.TextStyle(
                                      fontWeight: pw
                                          .FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding:
                                      const pw.EdgeInsets
                                          .all(6),
                                  child: pw.Text(
                                    'Amount',
                                    style: pw.TextStyle(
                                      fontWeight: pw
                                          .FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                    textAlign:
                                        pw.TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            ...widget.vendorBreakdown
                                .map((vendor) {
                              return pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding:
                                        const pw.EdgeInsets
                                            .all(6),
                                    child: pw.Text(
                                      vendor.vendorName,
                                      style:
                                          const pw.TextStyle(
                                              fontSize: 9),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding:
                                        const pw.EdgeInsets
                                            .all(6),
                                    child: pw.Text(
                                      widget.currency.format(
                                          vendor.total),
                                      textAlign: pw
                                          .TextAlign.right,
                                      style: pw.TextStyle(
                                        fontWeight: pw
                                            .FontWeight.bold,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 18),

            // ── AI Financial Insights ──
            pw.Text(
              'AI FINANCIAL INSIGHTS',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey200),
              ),
              child: pw.Text(
                aiSummary,
                style: const pw.TextStyle(
                  fontSize: 9.5,
                  lineSpacing: 1.4,
                ),
                textAlign: pw.TextAlign.justify,
              ),
            ),

            pw.SizedBox(height: 16),

            // ── Footer ──
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Text(
              'Generated by ScanPal on ${DateFormat('MMM d, y \'at\' h:mm a').format(DateTime.now())}',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey500,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Generating Report',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
            const SizedBox(height: 24),
            Text(
              _isGenerating
                  ? 'Generating your expense report...'
                  : 'Opening report...',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This may take a few seconds',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}