-- ============================================================================
-- PROBLEM B ACTIVITY LIBRARY SEED
-- WHO/CDC/NIMHANS-aligned starter set for caregiver + AWW workflows.
-- ============================================================================

INSERT INTO activity_library (
    title, description, instructions_english, instructions_telugu,
    domain, target_role, frequency, materials_needed, time_required_minutes,
    visual_aid_url, risk_bucket, target_completions
) VALUES
-- Gross Motor
('Tummy Time Practice', 'Strengthen neck and back muscles.',
 'Place child on tummy for 2-3 minutes, 3-4 times daily.',
 'ప్రతిరోజూ 3-4 సార్లు బిడ్డను కడుపుపై 2-3 నిమిషాలు పడుకోబెట్టండి.',
 'GM', 'CAREGIVER', 'DAILY', 'Soft mat', 5, '/visuals/tummy_time.jpg', 'HIGH', 7),
('Supported Sitting Practice', 'Build core stability.',
 'Seat child with cushion support and encourage reaching.',
 'దిండ్లతో సహాయం చేసి కూర్చోబెట్టండి, బొమ్మలను అందుకోవడానికి ప్రోత్సహించండి.',
 'GM', 'CAREGIVER', 'DAILY', 'Cushions, toys', 10, '/visuals/supported_sitting.jpg', 'HIGH', 7),
('Weekly GM Progress Check', 'Monitor gross motor milestones.',
 'Observe sitting, standing, and walking progress and record.',
 'కూర్చోవడం, నిలబడటం, నడక పురోగతిని గమనించి నమోదు చేయండి.',
 'GM', 'AWW', 'WEEKLY', 'AWW diary', 10, '/visuals/aww_monitor.jpg', 'ALL', 2),

-- Fine Motor
('Pincer Grasp Practice', 'Develop thumb-finger grasp.',
 'Offer small safe pieces and encourage picking with thumb and finger.',
 'చిన్న సురక్షిత వస్తువులను బొటనవేలు, చూపుడు వేలితో పట్టుకోవడానికి ప్రోత్సహించండి.',
 'FM', 'CAREGIVER', 'DAILY', 'Small safe food pieces', 5, '/visuals/pincer.jpg', 'HIGH', 7),
('Stacking Blocks', 'Improve hand-eye coordination.',
 'Show stacking 2-3 blocks and let child imitate.',
 '2-3 బ్లాకులు పేర్చడం చూపించి బిడ్డను అనుకరించనివ్వండి.',
 'FM', 'CAREGIVER', 'DAILY', 'Blocks', 5, '/visuals/stacking.jpg', 'ALL', 7),
('Weekly FM Progress Check', 'Monitor fine motor progression.',
 'Track grasp, stacking, and scribbling skills in diary.',
 'పట్టుకోవడం, పేర్చడం, గీతలు గీయడం నైపుణ్యాలను డైరీలో నమోదు చేయండి.',
 'FM', 'AWW', 'WEEKLY', 'AWW diary', 10, '/visuals/aww_monitor.jpg', 'ALL', 2),

-- Language and Communication
('Core Word Practice', 'Build first-word vocabulary.',
 'Practice 5 core words daily with real objects.',
 'నిజమైన వస్తువులతో ప్రతిరోజూ 5 కోర్ పదాలు ప్రాక్టీస్ చేయండి.',
 'LC', 'CAREGIVER', 'DAILY', 'Household objects', 10, '/visuals/word_practice.jpg', 'HIGH', 7),
('Picture Book Reading', 'Build receptive and expressive language.',
 'Read a picture book daily and name each object.',
 'ప్రతిరోజూ చిత్రాల పుస్తకం చదివి ప్రతి వస్తువు పేరు చెప్పండి.',
 'LC', 'CAREGIVER', 'DAILY', 'Picture book', 10, '/visuals/picture_reading.jpg', 'ALL', 7),
('Weekly LC Progress Check', 'Monitor speech and command-following.',
 'Record new words and command response accuracy.',
 'కొత్త పదాలు మరియు ఆదేశాలకు స్పందనను నమోదు చేయండి.',
 'LC', 'AWW', 'WEEKLY', 'AWW diary', 10, '/visuals/aww_monitor.jpg', 'ALL', 2),

-- Cognitive
('Object Permanence Game', 'Develop search and memory.',
 'Hide toy under cloth and ask child to find it.',
 'బొమ్మను గుడ్డ కింద దాచిపెట్టి కనుగొనమని అడగండి.',
 'COG', 'CAREGIVER', 'DAILY', 'Toy, cloth', 5, '/visuals/object_permanence.jpg', 'HIGH', 7),
('Matching Game', 'Improve visual discrimination.',
 'Match identical objects and gradually increase complexity.',
 'ఒకే విధమైన వస్తువులను జతపరచడం ప్రాక్టీస్ చేయండి.',
 'COG', 'CAREGIVER', 'DAILY', 'Pairs of objects', 5, '/visuals/matching.jpg', 'ALL', 7),
('Weekly COG Progress Check', 'Monitor cognitive play outcomes.',
 'Observe puzzle solving and matching performance.',
 'పజిల్ పరిష్కారం మరియు జతపరచే పనితీరును గమనించండి.',
 'COG', 'AWW', 'WEEKLY', 'AWW diary', 10, '/visuals/aww_monitor.jpg', 'ALL', 2),

-- Social-Emotional
('Peek-a-Boo Interaction', 'Improve social interaction.',
 'Play peek-a-boo and encourage turn taking.',
 'పీక్-ఎ-బూ ఆట ఆడి వంతులు మార్చుకోవడానికి ప్రోత్సహించండి.',
 'SE', 'CAREGIVER', 'DAILY', 'Small cloth', 5, '/visuals/peekaboo.jpg', 'ALL', 7),
('Imitate Actions', 'Promote imitation and shared attention.',
 'Clap, wave, and encourage child to copy.',
 'చప్పట్లు, చేయి ఊపడం చూపించి బిడ్డను అనుకరించనివ్వండి.',
 'SE', 'CAREGIVER', 'DAILY', 'None', 5, '/visuals/imitate.jpg', 'ALL', 7),
('Weekly SE Progress Check', 'Track social responses.',
 'Observe eye contact, smiles, and play interactions.',
 'కంటి చూపు, నవ్వు, ఆట పరస్పర చర్యలను గమనించండి.',
 'SE', 'AWW', 'WEEKLY', 'AWW diary', 10, '/visuals/aww_monitor.jpg', 'ALL', 2),

-- Neuro (Autism/ADHD support)
('Sensory Play - Water', 'Provide calming sensory regulation.',
 'Allow supervised water play and narrate sensations.',
 'పర్యవేక్షణతో నీటితో ఆట చేయనివ్వండి, అనుభూతులు వివరిస్తూ ఉండండి.',
 'NEURO', 'CAREGIVER', 'WEEKLY', 'Water, bowl', 15, '/visuals/water_play.jpg', 'HIGH', 2),
('Calming Corner', 'Create predictable calming space.',
 'Use cushions and quiet corner for emotional regulation.',
 'దిండ్లు, ప్రశాంత మూలతో భావోద్వేగ నియంత్రణకు సహాయం చేయండి.',
 'NEURO', 'BOTH', 'DAILY', 'Cushions, toys', 10, '/visuals/calming_corner.jpg', 'CRITICAL', 7),
('Visual Schedule Routine', 'Reduce transitions-related stress.',
 'Show picture schedule: first-next routine.',
 'చిత్రాల షెడ్యూల్ చూపించి "మొదట-తర్వాత" దినచర్యను పాటించండి.',
 'NEURO', 'BOTH', 'DAILY', 'Picture chart', 5, '/visuals/schedule.jpg', 'HIGH', 7),

-- General AWW activity
('Caregiver Coaching Session', 'Weekly caregiver capability building.',
 'Demonstrate 2-3 activities and observe caregiver practice.',
 '2-3 కార్యకలాపాలు చూపించి, సంరక్షకుడు ప్రాక్టీస్ చేయడాన్ని గమనించండి.',
 'GENERAL', 'AWW', 'WEEKLY', 'Activity materials', 20, '/visuals/coaching.jpg', 'ALL', 2)
ON CONFLICT DO NOTHING;
