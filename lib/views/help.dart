import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

class HelpView extends StatelessWidget {
  const HelpView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    Widget entry(String body) => ListItem(
      alignment: ListRowAlignment.top,
      title: Text(
        body,
        style: AppTextStyle.subheadline.of(context).copyWith(height: 1.45),
      ),
    );
    return Scaffold(
      title: l.help,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.sectionsTopPadding,
          16,
          24 + context.bottomInset,
        ),
        children: [
          Text(
            l.helpIntro,
            style: AppTextStyle.subheadline.of(context).toLighter,
          ),
          const SizedBox(height: 16),
          generateSection(
            title: l.helpConnectTitle,
            items: [entry(l.helpConnectBody)],
          ),
          generateSection(
            title: l.helpStatusTitle,
            items: [entry(l.helpStatusBody)],
          ),
          generateSection(
            title: l.helpTrafficTitle,
            items: [entry(l.helpTrafficBody)],
          ),
          generateSection(
            title: l.helpErrorsTitle,
            items: [entry(l.helpErrorsBody)],
          ),
          generateSection(
            title: l.helpGlossaryTitle,
            items: [
              entry(l.helpGlossaryAccess),
              entry(l.helpGlossaryProfile),
              entry(l.helpGlossaryVless),
              entry(l.helpGlossaryWdtt),
              entry(l.helpGlossaryByeDpi),
              entry(l.helpGlossarySubscription),
            ],
          ),
          generateSection(
            title: l.helpContactTitle,
            items: [entry(l.helpContactBody)],
          ),
        ],
      ),
    );
  }
}
