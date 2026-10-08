import 'package:flutter/material.dart';
import '../../../core/models/complaint.dart';
import '../../../core/repositories/complaint_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/complaint_card.dart';
import 'complaint_details_screen.dart';

class MyComplaintsScreen extends StatefulWidget {
  final ComplaintRepository? complaintRepository;

  const MyComplaintsScreen({super.key, this.complaintRepository});

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  late final ComplaintRepository _complaintRepo;
  List<Complaint> _myComplaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _complaintRepo = widget.complaintRepository ?? ComplaintRepository();
    _loadMyComplaints();
  }

  Future<void> _loadMyComplaints() async {
    setState(() => _isLoading = true);
    try {
      final list = await _complaintRepo.fetchMyComplaints();
      if (!mounted) return;
      setState(() {
        _myComplaints = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load your complaints: $e')),
      );
    }
  }

  Future<void> _confirmAndDelete(Complaint complaint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint?'),
        content: const Text(
          'Are you sure you want to delete this civic complaint? This will permanently remove the report, photo, and all community confirmations. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.priorityCritical,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _complaintRepo.deleteComplaint(complaint.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complaint deleted successfully.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      _loadMyComplaints();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete complaint: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text('My Reported Issues'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMyComplaints,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMyComplaints,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _myComplaints.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_turned_in_outlined, size: 56, color: Color(0xFF94A3B8)),
                          SizedBox(height: 16),
                          Text(
                            'No Issues Reported Yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'When you report civic issues like potholes or garbage, they will show up here so you can track progress.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _myComplaints.length,
                    itemBuilder: (context, index) {
                      final c = _myComplaints[index];
                      return ComplaintCard(
                        complaint: c,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => ComplaintDetailsScreen(
                                initialComplaint: c,
                                complaintRepository: _complaintRepo,
                              ),
                            ),
                          ).then((_) => _loadMyComplaints());
                        },
                        onDelete: () => _confirmAndDelete(c),
                      );
                    },
                  ),
      ),
    );
  }
}

