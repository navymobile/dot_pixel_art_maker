import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../domain/dot_model.dart';
import '../../domain/gen_logic.dart';
import '../../infra/qr_service.dart';

class ExchangeScreen extends StatefulWidget {
  final DotModel currentDot;

  const ExchangeScreen({super.key, required this.currentDot});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final DotModel? scannedDot = QrService.decode(barcode.rawValue!);
        if (scannedDot != null) {
          // Verify simple logic: Allow exchange if ID is different (or same for debug?)
          // For now, just accept it and increment gen

          if (mounted) {
            _scannerController.stop();
            // Increment gen logic here
            final newDot = GenLogic.incrementGen(scannedDot);
            Navigator.pop(context, newDot);
          }
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Generate QR data
    final qrData = QrService.encode(widget.currentDot);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exchange'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My QR Code', icon: Icon(Icons.qr_code)),
            Tab(text: 'Scan', icon: Icon(Icons.qr_code_scanner)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Show QR
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16.0),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 300.0,
                      gapless: true,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Show this to your friend'),
                  Text('DNA: ${widget.currentDot.id.substring(0, 8)}...'),
                ],
              ),
            ),
          ),
          // Scan QR
          Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
              ),
              const Center(
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2.0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
