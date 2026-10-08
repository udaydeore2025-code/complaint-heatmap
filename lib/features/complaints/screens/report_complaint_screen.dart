import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';

class ReportComplaintScreen extends StatefulWidget {
  final ComplaintRepository? complaintRepository;

  const ReportComplaintScreen({super.key, this.complaintRepository});

  @override
  State<ReportComplaintScreen> createState() => _ReportComplaintScreenState();
}

class _ReportComplaintScreenState extends State<ReportComplaintScreen> {
  late final ComplaintRepository _complaintRepository;
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedCategory = 'Pothole';
  XFile? _selectedImage;
  double? _latitude;
  double? _longitude;

  bool _isFetchingLocation = false;
  bool _isSubmitting = false;
  String? _locationStatusMessage;
  String? _submissionError;

  @override
  void initState() {
    super.initState();
    _complaintRepository = widget.complaintRepository ?? ComplaintRepository();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = picked;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick photo: $e')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload Complaint Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                title: const Text('Take Photo with Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppTheme.primaryColor),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUseCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _locationStatusMessage = 'Requesting GPS location...';
      _submissionError = null;
    });

    final position = await LocationService.getCurrentLocation();
    if (!mounted) return;

    if (position != null) {
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isFetchingLocation = false;
        _locationStatusMessage = 'Location captured successfully!';
      });
    } else {
      setState(() {
        _isFetchingLocation = false;
        _locationStatusMessage =
            'Unable to get GPS location. Please ensure location services are enabled and permissions granted.';
      });
    }
  }

  Future<void> _handleSubmitComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      setState(() {
        _submissionError = 'Please tap "USE CURRENT LOCATION" to capture issue coordinates.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });

    try {
      await _complaintRepository.createComplaint(
        category: _selectedCategory,
        description: _descriptionController.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        photo: _selectedImage,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complaint submitted successfully!'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submissionError = 'Submission failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('Report Civic Issue'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Error Banner
                if (_submissionError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(
                        left: BorderSide(color: Color(0xFFDC2626), width: 4),
                      ),
                    ),
                    child: Text(
                      _submissionError!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 1. Category Field
                const Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: ComplaintRepository.reportableCategories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 20),

                // 2. Description Field
                const Text(
                  'Description',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Describe the civic problem clearly (e.g., deep pothole causing traffic slowdown...)',
                    alignLabelWithHint: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().length < 5) {
                      return 'Please provide a description (at least 5 characters)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // 3. Optional Landmark / Address
                const Text(
                  'Landmark / Road Name (Optional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Near City Hospital, 5th Cross Road',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Photo Section
                const Text(
                  'Photo (Recommended)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (_selectedImage == null)
                  OutlinedButton.icon(
                    onPressed: _showImageSourceDialog,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add Photo (Camera / Gallery)'),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          height: 180,
                          width: double.infinity,
                          color: const Color(0xFFF1F5F9),
                          child: kIsWeb
                              ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                              : Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            radius: 18,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _selectedImage = null;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _showImageSourceDialog,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Change Photo'),
                  ),
                ],
                const SizedBox(height: 20),

                // 5. Location Section
                const Text(
                  'Issue Location',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Capture coordinates at the location of the reported issue.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 10),

                // Location action button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _latitude != null ? const Color(0xFF16A34A) : AppTheme.primaryColor,
                  ),
                  onPressed: _isFetchingLocation ? null : _handleUseCurrentLocation,
                  icon: _isFetchingLocation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(
                    _latitude != null ? 'UPDATE CURRENT LOCATION' : 'USE CURRENT LOCATION',
                  ),
                ),
                const SizedBox(height: 12),

                // Display Coordinates
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _latitude != null ? Icons.check_circle : Icons.info_outline,
                            color: _latitude != null ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _latitude != null
                                ? 'Coordinates Captured'
                                : 'Coordinates: Not Captured Yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _latitude != null ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (_latitude != null && _longitude != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Latitude: ${_latitude!.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Longitude: ${_longitude!.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        ),
                      ],
                      if (_locationStatusMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _locationStatusMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Submit Complaint Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isSubmitting ? null : _handleSubmitComplaint,
                  child: _isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('SUBMITTING COMPLAINT...'),
                          ],
                        )
                      : const Text(
                          'SUBMIT COMPLAINT',
                          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

