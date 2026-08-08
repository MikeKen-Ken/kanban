import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCompleted});

  final Future<void> Function() onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  var _page = 0;
  var _completing = false;

  static const _pages = [
    (
      icon: Icons.dashboard_customize_outlined,
      title: '按你的流程组织任务',
      description: '创建列和卡片，拖动调整进度；列可设置软性在制品上限。',
    ),
    (
      icon: Icons.calendar_month_outlined,
      title: '按日期安排任务',
      description: '在日历中查看到期日、选中今天即可看到当日任务，也可用组合筛选缩小范围。',
    ),
    (
      icon: Icons.cloud_sync_outlined,
      title: '在设备间保持一致',
      description: '在设置中配置 WebDAV，即可同步项目、标签、保存视图、模板和活动历史。',
    ),
  ];

  Future<void> _next() async {
    if (_page < _pages.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => _completing = true);
    await widget.onCompleted();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _completing ? null : widget.onCompleted,
                child: const Text('跳过'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Semantics(
                    label: '${page.title}。${page.description}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            page.icon,
                            size: 88,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            page.description,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _completing ? null : _next,
                  child: _completing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_page == _pages.length - 1 ? '开始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
