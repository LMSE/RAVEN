function metaCycMets=getMetsFromMetaCyc(metacycPath)
% getMetsFromMetaCyc
%   Retrieves information of all metabolites in MetaCyc database
%
%   Input:
%   metacycPath  if metacycMets.mat is not in the RAVEN\external\metacyc directory,
%                this function will attempt to build it by reading info from
%                a local dump of MetaCyc database, and metacycPath is the path
%                to the MetaCyc data files
%
%   Output:
%   model        a model structure generated from the database. The following
%                fields are filled
%                id:             'MetaCyc'
%                description:    'Automatically generated from MetaCyc database'
%                mets:           MetaCyc compound ids
%                metNames:       Compound name. Reuse compound id here if
%                                there is no name provided
%                metFormulas:    The chemical composition of the metabolite.
%                inchis:         InChI string for the metabolite
%                metCharges:     Compound charge state
%                metMiriams:     If there is a CHEBI id available, then that
%                                will be saved here
%                keggid:         The corresponding KEGG compound id if available
%                version:        MetaCyc database version
%
%   If the file metaCycMets.mat is in the RAVEN\external\metacyc directory
%   it will be directly loaded. Otherwise, it will be generated by parsing
%   the MetaCyc database files. In general, this metaCycMets.mat file should
%   be removed and rebuilt when a newer version of MetaCyc is released.
%               
%   Usage: model=getMetsFromMetaCyc(metacycPath)

% NOTE: This is how one entry looks in the file

% //                                                                                                                                                                                                                                                                                 
% UNIQUE-ID - CPD-18846
% TYPES - CPD-18866
% COMMON-NAME - 12-ethyl-8-propyl-bacteriochlorophyllide <i>d</i>
% ATOM-CHARGES - (43 -1)
% ATOM-CHARGES - (12 -1)
% CHEMICAL-FORMULA - (C 35)
% CHEMICAL-FORMULA - (H 36)
% CHEMICAL-FORMULA - (N 4)
% CHEMICAL-FORMULA - (O 4)
% CHEMICAL-FORMULA - (MG 1)
% CITATIONS - 26331578
% CITATIONS - 2350541
% CREDITS - SRI
% CREDITS - caspi
% MOLECULAR-WEIGHT - 600.999
% MONOISOTOPIC-MW - 602.274347629
% NON-STANDARD-INCHI - InChI=1S/C35H39N4O4.Mg/c1-7-9-21-16(3)24-14-29-32(19(6)40)18(5)26(37-29)13-25-17(4)22(10-11-31(42)43)34(38-25)23-12-30(41)33-20(8-2)27(39-35(23)33)15-28(21)36-24;/h12-15,17,19,22,40H,7-11H2,1-6H3,(H3,36,37,38,39,41,42,43);/q-1;+2/p-3/t17-,19?,22-;/m0./s1
% SMILES - CCCC5(=C(C)C9(N6([Mg]27(N1(C(C(C)C(CCC(=O)[O-])C=1C4([C-]C(=O)C3(=C(CC)C(N2C3=4)=CC5=6)))=CC8(=C(C)C(C(O)C)=C(N78)C=9))))))

% A line that contains only '//' separates each object.

% Check if the metabolites have been parsed before and saved. If so, load
% the model.
[ST, I]=dbstack('-completenames');
ravenPath=fileparts(fileparts(fileparts(ST(I).file)));
metsFile=fullfile(ravenPath,'external','metacyc','metaCycMets.mat');
metaCycMetFile='compounds.dat';

if exist(metsFile, 'file')
    fprintf(['Importing MetaCyc metabolites from ' strrep(metsFile,'\','/') '... ']);
    load(metsFile);
    fprintf('done\n');
else
    fprintf(['Cannot locate ' strrep(metsFile,'\','/') '\nNow try to generate it from local MetaCyc data files...\n']);
    if ~exist(fullfile(metacycPath,metaCycMetFile),'file')
        EM=fprintf(['The file of metabolites cannot be located, and should be downloaded from MetaCyc.\n']);
        dispEM(EM);
    else
        %Add new functionality in the order specified in models
        metaCycMets.id='MetaCyc';
        metaCycMets.description='Automatically generated from MetaCyc database';
        
        %Preallocate memory for 50000 metabolites
        metaCycMets.mets=cell(50000,1);
        metaCycMets.metNames=cell(50000,1);
        metaCycMets.metFormulas=cell(50000,1);
        metaCycMets.inchis=cell(50000,1);
        metaCycMets.metCharges=zeros(50000,1);
        metaCycMets.metMiriams=cell(50000,1);
        metaCycMets.keggid=cell(50000,1);
        
        %First load information on metabolite ID, name, formula, and others
        fid = fopen(fullfile(metacycPath,metaCycMetFile), 'r');
        
        %Keeps track of how many metabolites that have been added
        metCounter=0;
        
        %Loop through the file
        while 1
            %Get the next line
            tline = fgetl(fid);
            %disp(tline);
            
            % Abort at end of file
            if ~ischar(tline)
                break;
            end
            
            % Get the version of MetaCyc database
            if numel(tline)>11 && strcmp(tline(1:11),'# Version: ')
                metaCycMets.version=tline(12:end);
            end

            %Check if it is a new entry
            if numel(tline)>12 && strcmp(tline(1:12),'UNIQUE-ID - ')
                metCounter=metCounter+1;
                
                %Add empty strings as initial values
                metaCycMets.metNames{metCounter}='';
                metaCycMets.metFormulas{metCounter}='';
                metaCycMets.inchis{metCounter}='';
                %metaCycMets.smiles{metCounter}='';
                %metaCycMets.pubchem{metCounter}='';
                metaCycMets.keggid{metCounter}='';
                nonStandardInchis = '';
                
                %Add compound ID
                metaCycMets.mets{metCounter}=tline(13:end);
            end
            
            
            %Add name
            if numel(tline)>14 &&	strcmp(tline(1:14),'COMMON-NAME - ')
                metaCycMets.metNames{metCounter}=tline(15:end);
                
                %Romve HTML symbols
                metaCycMets.metNames{metCounter}=regexprep(metaCycMets.metNames{metCounter},'<(\w+)>','');
                metaCycMets.metNames{metCounter}=regexprep(metaCycMets.metNames{metCounter},'</(\w+)>','');
                metaCycMets.metNames{metCounter}=regexprep(metaCycMets.metNames{metCounter},'[&;]','');
            end
            
            %Add charge
            if numel(tline)>16 &&	strcmp(tline(1:16),'ATOM-CHARGES - (')
                atomCharge=tline(17:end-1);
                
                s=strfind(atomCharge,' ');
                if any(s)
                    atomCharge=atomCharge(s+1:end);
                    metaCycMets.metCharges(metCounter,1)=metaCycMets.metCharges(metCounter,1)+str2num(atomCharge);
                end
            end
            
            %Add inchis
            if numel(tline)>14 && strcmp(tline(1:14),'INCHI - InChI=')
                metaCycMets.inchis{metCounter}=tline(15:end);
            end
            
            %Add non-standard inchis
            if numel(tline)>27 && strcmp(tline(1:27),'NON-STANDARD-INCHI - InChI=')
                nonStandardInchis=tline(28:end);
            end
            
            %Add SMILES
            if numel(tline)>9 && strcmp(tline(1:9),'SMILES - ')
                
                if isstruct(metaCycMets.metMiriams{metCounter})
                    addToIndex=numel(metaCycMets.metMiriams{metCounter}.name)+1;
                else
                    addToIndex=1;
                end
                tempStruct=metaCycMets.metMiriams{metCounter};
                tempStruct.name{addToIndex,1}='SMILES';
                tempStruct.value{addToIndex,1}=tline(10:end);
                metaCycMets.metMiriams{metCounter}=tempStruct;
            end
            
            %Add formula
            if numel(tline)>20 && strcmp(tline(1:20),'CHEMICAL-FORMULA - (')
                metaCycMets.metFormulas{metCounter}=strcat(metaCycMets.metFormulas{metCounter},tline(21:end-1));
                metaCycMets.metFormulas{metCounter}(isspace(metaCycMets.metFormulas{metCounter})) = [];
            end
            
            %Add KEGG id
            if numel(tline)>23 && strcmp(tline(1:23),'DBLINKS - (LIGAND-CPD "')
                keggid=tline(24:end);
                
                s=strfind(keggid,'"');
                if any(s)
                    keggid=keggid(1:s-1);
                end
                
                metaCycMets.keggid{metCounter}=keggid;
            end
            
            %Add CHEBI id
            if numel(tline)>18 && strcmp(tline(1:18),'DBLINKS - (CHEBI "')
                chebiID=tline(20:end); %This is because there is sometimes more than one CHEBI index
                
                s=strfind(chebiID,'"');
                if any(s)
                    chebiID=chebiID(1:s-1);
                end
                
                if isstruct(metaCycMets.metMiriams{metCounter})
                    addToIndex=numel(metaCycMets.metMiriams{metCounter}.name)+1;
                else
                    addToIndex=1;
                end
                tempStruct=metaCycMets.metMiriams{metCounter};
                tempStruct.name{addToIndex,1}='chebi';
                tempStruct.value{addToIndex,1}=strcat('CHEBI:',chebiID);
                metaCycMets.metMiriams{metCounter}=tempStruct;
            end
            
            %Add PubChem
            if numel(tline)>20 && strcmp(tline(1:20),'DBLINKS - (PUBCHEM "')
                pubchemID=tline(21:end);
                
                s=strfind(pubchemID,'"');
                if any(s)
                    pubchemID=pubchemID(1:s-1);
                end
                
                if isstruct(metaCycMets.metMiriams{metCounter})
                    addToIndex=numel(metaCycMets.metMiriams{metCounter}.name)+1;
                else
                    addToIndex=1;
                end
                tempStruct=metaCycMets.metMiriams{metCounter};
                tempStruct.name{addToIndex,1}='pubchem.compound';
                tempStruct.value{addToIndex,1}=pubchemID;
                metaCycMets.metMiriams{metCounter}=tempStruct;
            end
            
            %Add non-standard inchis when standard one is unavailable
            if strcmp(tline,'//') && strcmp(metaCycMets.inchis{metCounter},'')
                metaCycMets.inchis{metCounter}=nonStandardInchis;
                nonStandardInchis = '';
                
                %Refine formula from inchis
                s=strfind(metaCycMets.inchis{metCounter},'/');
                if any(s)
                    inchiFormula=metaCycMets.inchis{metCounter}(s(1)+1:s(2)-1);
                    
                    %And remove dot characters
                    inchiFormula(regexp(inchiFormula,'[.]'))=[];
                    if ~strcmp(metaCycMets.metFormulas{metCounter},inchiFormula)
                        metaCycMets.metFormulas{metCounter}=inchiFormula;
                    end
                end
                
            end
            
        end
        
        %Close the file
        fclose(fid);
        
        %If too much space was allocated, shrink the model
        metaCycMets.mets=metaCycMets.mets(1:metCounter);
        metaCycMets.metNames=metaCycMets.metNames(1:metCounter);
        metaCycMets.metFormulas=metaCycMets.metFormulas(1:metCounter);
        metaCycMets.metMiriams=metaCycMets.metMiriams(1:metCounter);
        metaCycMets.inchis=metaCycMets.inchis(1:metCounter);
        metaCycMets.metCharges=metaCycMets.metCharges(1:metCounter,:);
        %metaCycMets.smiles=metaCycMets.smiles(1:metCounter);
        %metaCycMets.pubchem=metaCycMets.pubchem(1:metCounter);
        metaCycMets.keggid=metaCycMets.keggid(1:metCounter);
        
        %If the metMiriams structure is empty, use MetaCyc id as metMiriams
        for i=1:numel(metaCycMets.mets)
            if ~isstruct(metaCycMets.metMiriams{i})
                miriamStruct.name{1}='metacyc.compound';
                miriamStruct.value{1}=metaCycMets.mets{i};
                metaCycMets.metMiriams{i}=miriamStruct;
            end
        end
        
        %Saves the model
        save(metsFile,'metaCycMets');
        fprintf(['New metaCycMets.mat has been successfully updated!\n\n']);
    end
end
end
