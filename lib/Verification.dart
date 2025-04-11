import 'package:flutter/material.dart';


class VerificationPage extends StatelessWidget {
  final String question;
  final String questionKey;
  final List<String>? subQuestions;
  final VerificationPage? nextPage;
  final bool isLastPage;
  final Map<String, bool> answers;

  VerificationPage({
    Key? key,
    required this.question,
    required this.questionKey,
    this.subQuestions,
    this.nextPage,
    this.isLastPage = false,
    Map<String, bool>? answers,
  })  : answers = answers ?? {},
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xffA5231D), // Deep red background color
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 8, 
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                    left: 24,
                    right: 24,
                  ),
                  child: _buildCard(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 24),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16),
          Text(
            question,
            style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          if (subQuestions != null) ...[
            SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: subQuestions!.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "• $item",
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                );
              }).toList(),
            ),
          ],
          SizedBox(height: 32),
          _buildButton(context, "Yes", true),
          SizedBox(height: 16),
          _buildButton(context, "No", false),
          SizedBox(height: 24),
          if (nextPage != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => nextPage!.copyWith(
                        answers: {...answers},
                      ),
                    ),
                  ).then((value) {
                    if (value != null) {
                      Navigator.pop(context, value);
                    }
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Skip",
                      style: TextStyle(
                        color: Color(0xffA5231D),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Color(0xffA5231D),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Center element
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "${_getPageNumber()}/4",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          
          // Left and right navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () {
                  Navigator.pop(context, answers);
                },
              ),
              if (nextPage != null)
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => nextPage!.copyWith(
                          answers: {...answers},
                        ),
                      ),
                    ).then((value) {
                      if (value != null) {
                        Navigator.pop(context, value);
                      }
                    });
                  },
                )
              else
                SizedBox(width: 48), // Placeholder for alignment
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, String text, bool response) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: () {
          answers[questionKey] = response;

          if (isLastPage) {
            Navigator.pop(context, answers);
          } else if (nextPage != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => nextPage!.copyWith(answers: {...answers}),
              ),
            ).then((value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            });
          }
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Color(0xffA5231D), width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: Colors.white,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  int _getPageNumber() {
    if (question.contains("weight")) return 1;
    if (question.contains("suffering")) return 2;
    if (question.contains("tattoo")) return 3;
    if (question.contains("immunization")) return 4;
    return 1;
  }

  VerificationPage copyWith({Map<String, bool>? answers}) {
    return VerificationPage(
      question: question,
      questionKey: questionKey,
      subQuestions: subQuestions,
      nextPage: nextPage?.copyWith(answers: answers),
      isLastPage: isLastPage,
      answers: answers ?? this.answers,
    );
  }
}